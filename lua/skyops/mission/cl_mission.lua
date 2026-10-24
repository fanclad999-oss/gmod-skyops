-- SkyOps: состояние миссии на клиенте (client)
-- Принимает брифинг, лобби, задачи, радио и итоги от сервера; интерфейс читает SkyOps.Client.

SkyOps = SkyOps or {}
SkyOps.Missions = SkyOps.Missions or {}

local M = SkyOps.Missions

SkyOps.Client = SkyOps.Client or {
	state = 0,
	missionId = nil,
	startTime = 0,
	brief = nil,
	lobby = nil,
	lobbyTime = 0,
	objState = {},
	unitDown = {},
	messages = {},
	list = {},
	debrief = nil,
}

local C = SkyOps.Client

local function ReadTable()
	local len = net.ReadUInt( 32 )
	local data = net.ReadData( len )
	local json = util.Decompress( data )

	return json and util.JSONToTable( json ) or nil
end

local function UIcall( name, ... )
	local UI = SkyOps.UI

	if UI and UI[ name ] then return UI[ name ]( ... ) end
end

net.Receive( "skyops_brief", function()
	C.brief = ReadTable()
	C.objState = {}
	C.unitDown = {}
	C.debrief = nil

	hook.Run( "SkyOps.BriefReceived", C.brief )
end )

net.Receive( "skyops_unitdown", function()
	C.unitDown = C.unitDown or {}
	C.unitDown[ net.ReadString() ] = true
end )

net.Receive( "skyops_lobby", function()
	C.lobby = ReadTable()
	C.lobbyTime = CurTime()

	hook.Run( "SkyOps.LobbyChanged", C.lobby )
end )

net.Receive( "skyops_state", function()
	local old = C.state

	C.state = net.ReadUInt( 4 )
	C.missionId = net.ReadString()
	C.startTime = net.ReadFloat()

	if C.state == M.STATE_BRIEFING then
		UIcall( "CloseDebrief" )
		UIcall( "OpenBriefing" )
	elseif C.state == M.STATE_RUNNING then
		UIcall( "CloseBriefing" )

		if old == M.STATE_BRIEFING then
			surface.PlaySound( "buttons/button24.wav" )
		end
	elseif C.state == M.STATE_IDLE then
		UIcall( "CloseBriefing" )
		UIcall( "CloseDebrief" )

		C.brief = nil
		C.lobby = nil
		C.objState = {}
	end

	hook.Run( "SkyOps.StateChanged", C.state, old )
end )

net.Receive( "skyops_obj", function()
	local list = ReadTable() or {}

	for _, entry in ipairs( list ) do
		local prev = C.objState[ entry.id ]

		if prev and prev.state ~= entry.state and entry.state == M.OBJ_DONE then
			surface.PlaySound( "buttons/blip1.wav" )
		end

		C.objState[ entry.id ] = entry
	end

	hook.Run( "SkyOps.ObjectivesChanged" )
end )

net.Receive( "skyops_msg", function()
	local sender = net.ReadString()
	local text = net.ReadString()

	table.insert( C.messages, { sender = sender, text = text, time = CurTime() } )

	while #C.messages > 6 do
		table.remove( C.messages, 1 )
	end

	surface.PlaySound( "npc/combine_soldier/vo/on1.wav" )
end )

net.Receive( "skyops_debrief", function()
	C.debrief = ReadTable()

	UIcall( "OpenDebrief" )
end )

net.Receive( "skyops_list", function()
	C.list = ReadTable() or {}

	hook.Run( "SkyOps.MissionListChanged", C.list )
end )

hook.Add( "InitPostEntity", "SkyOps.Sync", function()
	net.Start( "skyops_sync" )
	net.SendToServer()
end )

-- Помощники для интерфейса

function C.Objectives()
	local list = {}

	if not C.brief then return list end

	for _, obj in ipairs( C.brief.objectives or {} ) do
		local st = C.objState[ obj.id ] or {}

		table.insert( list, {
			id = obj.id,
			text = obj.text,
			optional = obj.optional,
			type = obj.type,
			waypoint = obj.waypoint,
			state = st.state or M.OBJ_PENDING,
			progress = st.progress,
			progressText = st.progressText,
		} )
	end

	return list
end

function C.Waypoint( id )
	if not C.brief then return nil end

	for _, wp in ipairs( C.brief.waypoints or {} ) do
		if wp.id == id then return wp end
	end
end

-- Текущая точка маршрута: WP активной задачи, иначе первая ещё не пройденная
function C.SteerpointWaypoint()
	if not C.brief then return nil end

	for _, obj in ipairs( C.Objectives() ) do
		if obj.state == M.OBJ_ACTIVE and obj.waypoint then
			return C.Waypoint( obj.waypoint )
		end
	end

	return nil
end

function C.ToVector( t )
	return Vector( t.x, t.y, t.z )
end

-- Мировая позиция (с учётом чанков InfMap) -> позиция, пригодная для ToScreen на этом клиенте
function C.WorldToLocal( pos )
	local lp = LocalPlayer()

	if InfMap and IsValid( lp ) and lp.CHUNK_OFFSET then
		return pos - InfMap.unlocalize_vector( Vector( 0, 0, 0 ), lp.CHUNK_OFFSET )
	end

	return pos
end

-- Мировая позиция сущности (как на сервере)
function C.WorldPos( ent )
	if InfMap and ent.CHUNK_OFFSET and ent.InfMap_GetPos then
		return InfMap.unlocalize_vector( ent:InfMap_GetPos(), ent.CHUNK_OFFSET )
	end

	return ent:GetPos()
end

function C.MySeat()
	local lobby = C.lobby
	local lp = LocalPlayer()

	if not lobby or not IsValid( lp ) then return nil end

	for i, flight in ipairs( lobby.flights or {} ) do
		if flight.pilotId == lp:UserID() then return i, M.SEAT_PILOT end
		if flight.wsoId == lp:UserID() then return i, M.SEAT_WSO end
	end
end

function C.RequestSeat( flight, seat, aircraft )
	net.Start( "skyops_slot" )
		net.WriteUInt( flight or 0, 4 )
		net.WriteUInt( seat or 0, 2 )
		net.WriteUInt( aircraft or 0, 4 )
	net.SendToServer()
end

function C.RequestLoadout( flight, id )
	net.Start( "skyops_loadout" )
		net.WriteUInt( flight, 4 )
		net.WriteUInt( id, 8 )
	net.SendToServer()
end

function C.SetReady( ready )
	net.Start( "skyops_ready" )
		net.WriteBool( ready )
	net.SendToServer()
end

concommand.Add( "skyops_briefing", function()
	if C.brief and C.state == M.STATE_BRIEFING then UIcall( "OpenBriefing" ) end
end )

concommand.Add( "skyops_debrief", function()
	if C.debrief then UIcall( "OpenDebrief" ) end
end )

concommand.Add( "skyops_missions", function()
	net.Start( "skyops_sync" )
	net.SendToServer()

	UIcall( "OpenMissionList" )
end )
