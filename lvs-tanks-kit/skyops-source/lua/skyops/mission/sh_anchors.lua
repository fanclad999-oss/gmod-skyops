-- SkyOps: помощники к якорям карты для миссий (shared: клиенту нужны север и уровень моря для HUD)
-- Сами якоря хранит ядро (SkyOps.Map.Register / SkyOps.Map.Anchor), здесь маршруты,
-- угол якоря, параметры карты и команда для снятия координат.

SkyOps = SkyOps or {}
SkyOps.Map = SkyOps.Map or { Anchors = {} }
SkyOps.Maps = SkyOps.Maps or {}

local Map = SkyOps.Map

function Map.GetCurrentDef()
	local mapname = game.GetMap():lower()

	for key, def in pairs( SkyOps.Maps ) do
		if def.match and string.find( mapname, def.match, 1, true ) then
			return def, key
		end
	end

	return nil
end

function Map.AnchorAngle( name )
	local a = Map.Anchors[ name ]

	return a and a.ang and Angle( a.ang ) or Angle( 0, 0, 0 )
end

-- Маршрут: список мировых позиций по именам якорей
function Map.Route( name )
	local def = Map.GetCurrentDef()

	if not def or not def.routes or not def.routes[ name ] then return nil end

	local points = {}

	for _, anchor in ipairs( def.routes[ name ] ) do
		local pos = Map.Anchor( anchor )

		if pos then table.insert( points, pos ) end
	end

	return points
end

function Map.IsTodo( name )
	local a = Map.Anchors[ name ]

	return a ~= nil and a.todo == true
end

function Map.NorthYaw()
	local def = Map.GetCurrentDef()

	return def and def.north_yaw or 90
end

function Map.SeaLevel()
	local def = Map.GetCurrentDef()

	return def and def.sea_level or 0
end

if CLIENT then return end

-- skyops_anchor_here <имя>: печатает строку для файла карты с позицией игрока или его самолёта
concommand.Add( "skyops_anchor_here", function( ply, cmd, args )
	if not IsValid( ply ) or not ply:IsAdmin() then return end

	local name = args[1] or "anchor"
	local ent = ply

	if ply.lvsGetVehicle and IsValid( ply:lvsGetVehicle() ) then
		ent = ply:lvsGetVehicle()
	end

	local pos = ent.InfMap_GetPos and ent:InfMap_GetPos() or ent:GetPos()
	local chunk = ent.CHUNK_OFFSET or Vector( 0, 0, 0 )
	local yaw = ent:GetAngles().y

	local line = string.format( "SkyOps.Map.Register( \"%s\", { chunk = Vector( %d, %d, %d ), pos = Vector( %d, %d, %d ), ang = Angle( 0, %d, 0 ) } )",
		name, chunk.x, chunk.y, chunk.z, pos.x, pos.y, pos.z, yaw )

	ply:PrintMessage( HUD_PRINTCONSOLE, line )
	ply:ChatPrint( "[SkyOps] Якорь записан в консоль: " .. name )
	print( "[SkyOps] " .. line )
end )
