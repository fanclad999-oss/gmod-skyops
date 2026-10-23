-- SkyOps: движок миссий (server)
-- Брифинг и лобби экипажей -> вылет -> проверка задач -> итоги.
-- Спавн самолётов и ПВО делает ядро (SkyOps.Spawn.*), этот модуль только раскладывает миссию.

SkyOps = SkyOps or {}
SkyOps.Missions = SkyOps.Missions or {}
SkyOps.Conv = SkyOps.Conv or {}

local M = SkyOps.Missions
local U = SkyOps.Conv

for _, name in ipairs( M.NET or {} ) do
	util.AddNetworkString( name )
end

local cvBriefTime = CreateConVar( "skyops_brief_time", "120", FCVAR_ARCHIVE, "Сколько секунд длится брифинг, пока экипажи выбирают места" )
local cvLaunchDelay = CreateConVar( "skyops_launch_delay", "5", FCVAR_ARCHIVE, "Отсчёт до вылета, когда все готовы" )

local function SendTable( msg, tbl, target )
	local data = util.Compress( util.TableToJSON( tbl ) )

	net.Start( msg )
		net.WriteUInt( #data, 32 )
		net.WriteData( data, #data )

	if target then net.Send( target ) else net.Broadcast() end
end

local function IsAdmin( ply )
	return not IsValid( ply ) or ply:IsAdmin() or game.SinglePlayer()
end

local function PosTable( pos )
	return { x = pos.x, y = pos.y, z = pos.z }
end

-- Группа юнитов миссии
local Group = {}
Group.__index = Group

function Group:Alive()
	local alive = {}

	for _, ent in ipairs( self.ents ) do
		if IsValid( ent ) and not self.dead[ ent ] then
			table.insert( alive, ent )
		end
	end

	return alive
end

-- Запуск миссии
local Run = {}
Run.__index = Run

function Run:Jets()
	local jets = {}

	for _, flight in ipairs( self.flights ) do
		if IsValid( flight.jet ) and (not flight.jet.GetHP or flight.jet:GetHP() > 0) then
			table.insert( jets, flight.jet )
		end
	end

	return jets
end

function Run:SeatedPlayers()
	local plys = {}

	for _, flight in ipairs( self.flights ) do
		if IsValid( flight.pilot ) then table.insert( plys, flight.pilot ) end
		if IsValid( flight.wso ) then table.insert( plys, flight.wso ) end
	end

	return plys
end

function Run:Stat( ply )
	local sid = ply:SteamID()

	self.stats[ sid ] = self.stats[ sid ] or { name = ply:Nick(), kills = 0, killsByGroup = {} }

	return self.stats[ sid ]
end

function Run:Radio( sender, text, target )
	net.Start( "skyops_msg" )
		net.WriteString( sender )
		net.WriteString( text )

	if target then net.Send( target ) else net.Broadcast() end
end

function Run:FlightCallsign( index )
	return self.def.callsign .. "-" .. index
end

-- Брифинг: всё, что не меняется во время лобби
function Run:BuildBrief()
	local def = self.def
	local brief = {
		id = def.id,
		name = def.name,
		type = def.type,
		typeName = M.ObjectiveTypeName[ def.type ] or string.upper( def.type or "" ),
		briefing = def.briefing or {},
		aircraft = {},
		waypoints = {},
		threats = {},
		targets = {},
		objectives = {},
		north_yaw = SkyOps.Map.NorthYaw(),
		todoAnchors = self.todoAnchors,
	}

	for _, ac in ipairs( def.aircraft ) do
		local reg = SkyOps.Registry and SkyOps.Registry.GetAircraft( ac.role )

		local allowed, always = M.AllowedLoadouts( ac )

		table.insert( brief.aircraft, {
			role = ac.role,
			crew = ac.crew or 2,
			name = ac.name or (reg and reg.name) or ac.role,
			loadouts = allowed,
			always = always,
			loadoutText = ac.loadout_text,
		} )
	end

	local startPos = SkyOps.Map.Anchor( def.start.anchor )
	if startPos then brief.start = PosTable( startPos ) end

	for _, wp in ipairs( def.waypoints or {} ) do
		local w = self.waypoints[ wp.id ]

		if w then
			table.insert( brief.waypoints, { id = wp.id, label = wp.label, pos = PosTable( w.pos ), radius = w.radius } )
		end
	end

	for _, unit in ipairs( def.units or {} ) do
		if unit.briefing then
			local pos = self.unitPos[ unit.id ]

			if pos then
				local entry = { id = unit.id, label = unit.label, kind = unit.kind, system = unit.system, role = unit.role, count = unit.count or 1, pos = PosTable( pos ) }

				if unit.kind == "airdefense" then
					local range = M.ThreatRange[ unit.system ]

					local reg = SkyOps.Registry and SkyOps.Registry.GetAirDefense and SkyOps.Registry.GetAirDefense( unit.system )

					if reg and reg.radar and reg.radar.engage then
						range = reg.radar.engage
					end

					entry.range = range
					entry.label = entry.label or M.ThreatName[ unit.system ] or unit.system

					table.insert( brief.threats, entry )
				elseif unit.team == "enemy" and unit.kind == "aiflight" then
					table.insert( brief.threats, entry )
				else
					table.insert( brief.targets, entry )
				end
			end
		end
	end

	for _, obj in ipairs( def.objectives ) do
		table.insert( brief.objectives, { id = obj.id, text = obj.text, optional = obj.optional == true, type = obj.type, waypoint = obj.waypoint, unit = obj.unit } )
	end

	return brief
end

function Run:BuildLobby()
	local lobby = { flights = {}, launchIn = nil, briefEndsIn = math.max( self.briefEnds - CurTime(), 0 ) }

	if self.launchAt then lobby.launchIn = math.max( self.launchAt - CurTime(), 0 ) end

	for i, flight in ipairs( self.flights ) do
		local ac = self.def.aircraft[ flight.aircraft ]

		lobby.flights[ i ] = {
			callsign = self:FlightCallsign( i ),
			aircraft = flight.aircraft,
			loadout = flight.loadout,
			crew = ac.crew or 2,
			pilot = IsValid( flight.pilot ) and flight.pilot:Nick() or nil,
			pilotId = IsValid( flight.pilot ) and flight.pilot:UserID() or nil,
			wso = IsValid( flight.wso ) and flight.wso:Nick() or nil,
			wsoId = IsValid( flight.wso ) and flight.wso:UserID() or nil,
			pilotReady = IsValid( flight.pilot ) and flight.ready[ flight.pilot ] == true,
			wsoReady = IsValid( flight.wso ) and flight.ready[ flight.wso ] == true,
		}
	end

	return lobby
end

function Run:BuildObjectives()
	local list = {}

	for _, obj in ipairs( self.objectives ) do
		table.insert( list, { id = obj.def.id, state = obj.state, progress = obj.progress, progressText = obj.progressText } )
	end

	return list
end

function Run:SendBrief( target ) SendTable( "skyops_brief", self.brief, target ) end
function Run:SendLobby( target ) SendTable( "skyops_lobby", self:BuildLobby(), target ) end
function Run:SendObjectives( target ) SendTable( "skyops_obj", self:BuildObjectives(), target ) end

function Run:SendState( target )
	net.Start( "skyops_state" )
		net.WriteUInt( self.state, 4 )
		net.WriteString( self.def.id )
		net.WriteFloat( self.startTime or 0 )

	if target then net.Send( target ) else net.Broadcast() end
end

-- Лобби: занять место
function Run:FindSeat( ply )
	for i, flight in ipairs( self.flights ) do
		if flight.pilot == ply then return i, M.SEAT_PILOT end
		if flight.wso == ply then return i, M.SEAT_WSO end
	end
end

function Run:LeaveSeat( ply )
	local i, seat = self:FindSeat( ply )

	if not i then return end

	local flight = self.flights[ i ]

	flight.ready[ ply ] = nil

	if seat == M.SEAT_PILOT then flight.pilot = nil else flight.wso = nil end
end

function Run:TakeSeat( ply, index, seat, aircraft )
	if self.state ~= M.STATE_BRIEFING then return end

	local flight = self.flights[ index ]

	if not flight then return end

	-- Самолёт выбирает пилот
	if seat == M.SEAT_PILOT and aircraft and self.def.aircraft[ aircraft ] then
		if flight.pilot == nil or flight.pilot == ply then
			if flight.aircraft ~= aircraft then
				flight.aircraft = aircraft
				flight.loadout = M.DefaultLoadout( self.def.aircraft[ aircraft ] )
			end

			-- одноместный самолёт: штурмана высаживаем
			if (self.def.aircraft[ aircraft ].crew or 2) < 2 and IsValid( flight.wso ) then
				self:LeaveSeat( flight.wso )
			end
		end
	end

	if seat == M.SEAT_PILOT then
		if IsValid( flight.pilot ) and flight.pilot ~= ply then return end

		self:LeaveSeat( ply )
		flight.pilot = ply
	elseif seat == M.SEAT_WSO then
		if (self.def.aircraft[ flight.aircraft ].crew or 2) < 2 then return end
		if IsValid( flight.wso ) and flight.wso ~= ply then return end

		self:LeaveSeat( ply )
		flight.wso = ply
	end

	self.launchAt = nil
	self:SendLobby()
end

function Run:SetReady( ply, ready )
	local i = self:FindSeat( ply )

	if not i then return end

	self.flights[ i ].ready[ ply ] = ready or nil

	local seated = self:SeatedPlayers()
	local all = #seated > 0

	for _, p in ipairs( seated ) do
		local fi = self:FindSeat( p )

		if not self.flights[ fi ].ready[ p ] then
			all = false

			break
		end
	end

	if all then
		self.launchAt = CurTime() + cvLaunchDelay:GetFloat()
	else
		self.launchAt = nil
	end

	self:SendLobby()
end

-- Спавн юнитов миссии через API ядра
function Run:ResolveUnitPositions()
	self.unitPos = {}
	self.todoAnchors = {}

	local function CheckTodo( name )
		if name and SkyOps.Map.IsTodo( name ) then self.todoAnchors[ name ] = true end
	end

	CheckTodo( self.def.start.anchor )

	for _, wp in ipairs( self.def.waypoints or {} ) do
		CheckTodo( wp.anchor )
	end

	for _, unit in ipairs( self.def.units or {} ) do
		local pos

		if unit.anchor then
			pos = SkyOps.Map.Anchor( unit.anchor )
			CheckTodo( unit.anchor )
		elseif unit.route then
			local route = SkyOps.Map.Route( unit.route )

			pos = route and route[1]
		end

		self.unitPos[ unit.id ] = pos
	end

	-- Юниты, которые следуют за другой группой, показываем на её месте
	for _, unit in ipairs( self.def.units or {} ) do
		if not self.unitPos[ unit.id ] and unit.follow then
			self.unitPos[ unit.id ] = self.unitPos[ unit.follow ]
		end
	end

	local list = {}
	for name in pairs( self.todoAnchors ) do table.insert( list, name ) end
	self.todoAnchors = list
end

local function ToEntList( result )
	if IsEntity( result ) then return IsValid( result ) and { result } or {} end
	if istable( result ) then
		local list = {}

		for _, ent in pairs( result.ents or result ) do
			if IsEntity( ent ) and IsValid( ent ) then table.insert( list, ent ) end
		end

		return list
	end

	return {}
end

function Run:SpawnUnit( unit )
	local Spawn = SkyOps.Spawn or {}
	local pos = self.unitPos[ unit.id ]
	local Teams = SkyOps.Teams or { BLUE = 1, RED = 2 }
	local opts = {
		count = unit.count,
		part = unit.part,
		team = unit.team == "friendly" and Teams.BLUE or Teams.RED,
		groupId = unit.id,
	}

	if unit.follow and self.groups[ unit.follow ] then
		opts.follow = self.groups[ unit.follow ].ents
	end

	local result

	if unit.kind == "airdefense" then
		if not Spawn.AirDefense then return nil, "нет SkyOps.Spawn.AirDefense" end
		if not pos then return nil, "нет позиции" end

		-- Части одного комплекса (РЛС, СНР, пусковые) создаёт сам комплекс: спавним его один раз,
		-- а нужные части находим рядом по классу (CollectParts)
		if unit.part then
			local key = unit.system .. "@" .. tostring( unit.anchor )

			if not self.sites[ key ] then
				self.sites[ key ] = ToEntList( Spawn.AirDefense( unit.system, pos, opts ) )
			end

			self.unitSite[ unit.id ] = key

			return {}, nil, true
		end

		result = Spawn.AirDefense( unit.system, pos, opts )
	elseif unit.kind == "convoy" then
		if not Spawn.Convoy then return nil, "нет SkyOps.Spawn.Convoy" end

		local route = unit.route and SkyOps.Map.Route( unit.route )

		if not route or #route == 0 then return nil, "нет маршрута " .. tostring( unit.route ) end

		result = Spawn.Convoy( unit.class, unit.count or 1, route, opts )
	elseif unit.kind == "aiflight" then
		if not Spawn.AIFlight then return nil, "нет SkyOps.Spawn.AIFlight" end
		if not pos then return nil, "нет позиции" end

		local task = {}

		for key, value in pairs( unit.task or {} ) do
			if self.groups[ value ] then
				task[ key ] = self.groups[ value ].ents
			else
				task[ key ] = SkyOps.Map.Anchor( value ) or value
			end
		end

		result = Spawn.AIFlight( unit.role, unit.count or 1, pos, task, opts )
	elseif unit.kind == "static" then
		if not pos then return nil, "нет позиции" end

		local ent = ents.Create( unit.class )

		if not IsValid( ent ) then return nil, "нет класса " .. tostring( unit.class ) end

		ent:SetPos( pos )
		ent:Spawn()

		result = ent
	else
		return nil, "неизвестный kind " .. tostring( unit.kind )
	end

	return ToEntList( result )
end

function Run:AddToGroup( group, ent )
	if self.entGroup[ ent ] then return end

	table.insert( group.ents, ent )
	group.total = #group.ents

	self.entGroup[ ent ] = group.id
	ent.SkyOpsMissionGroup = group.id

	if SkyOps.Units and SkyOps.Units.Register and not (SkyOps.Units.list and SkyOps.Units.list[ ent ]) then
		SkyOps.Units.Register( ent, group.id )
	end
end

-- Ядро сообщает о готовом комплексе: раскладываем его части по группам миссии
function Run:OnAirDefenseReady( main, parts )
	local key

	for k, list in pairs( self.sites ) do
		for _, ent in ipairs( list ) do
			if ent == main then key = k end
		end
	end

	if not key then return end

	for _, unit in ipairs( self.def.units or {} ) do
		local group = self.groups[ unit.id ]

		if group and group.pending and self.unitSite[ unit.id ] == key and parts[ unit.part ] then
			group.pending = nil

			for _, ent in ipairs( ToEntList( parts[ unit.part ] ) ) do
				if not unit.count or group.total < unit.count then
					self:AddToGroup( group, ent )
				end
			end
		end
	end
end

-- Запасной вариант, если ядро не прислало SkyOps.AirDefenseReady: ищем части рядом по классу
function Run:CollectParts()
	local Registry = SkyOps.Registry

	for _, unit in ipairs( self.def.units or {} ) do
		local group = self.groups[ unit.id ]

		if group and group.pending then
			group.pending = nil

			local data = Registry and Registry.GetAirDefense( unit.system )
			local class = data and data.parts and data.parts[ unit.part ]
			local pos = self.unitPos[ unit.id ]

			if class and pos then
				for _, ent in ipairs( ents.FindInSphere( pos, U.FromMeters( 400 ) ) ) do
					if ent:GetClass() == class and (not unit.count or group.total < unit.count) then
						self:AddToGroup( group, ent )
					end
				end
			end

			if group.total == 0 then
				ErrorNoHalt( "[SkyOps] " .. self.def.id .. ": не найдена часть " .. tostring( unit.part ) .. " комплекса " .. tostring( unit.system ) .. "\n" )
			end
		end
	end
end

function Run:SpawnUnits()
	self.sites = {}

	for _, unit in ipairs( self.def.units or {} ) do
		local list, err, pending = self:SpawnUnit( unit )
		local group = setmetatable( { id = unit.id, ents = {}, dead = {}, killed = 0, total = 0, pending = pending }, Group )

		self.groups[ unit.id ] = group

		for _, ent in ipairs( list or {} ) do
			self:AddToGroup( group, ent )
		end

		if err then
			ErrorNoHalt( "[SkyOps] " .. self.def.id .. ": юнит " .. unit.id .. " не создан: " .. err .. "\n" )
		end
	end

	timer.Simple( 1, function()
		if M.Active == self then self:CollectParts() end
	end )
end

function Run:SpawnFlights()
	local Spawn = SkyOps.Spawn or {}
	local start = self.def.start
	local basePos = SkyOps.Map.Anchor( start.anchor )
	local baseAng = SkyOps.Map.AnchorAngle( start.anchor )

	if not basePos then
		ErrorNoHalt( "[SkyOps] нет якоря старта " .. tostring( start.anchor ) .. "\n" )

		return false
	end

	if not Spawn.PlayerJet then
		self:Radio( "SkyOps", "Ядро аддона не загружено: нет SkyOps.Spawn.PlayerJet" )

		return false
	end

	local spawned = 0

	for i, flight in ipairs( self.flights ) do
		if IsValid( flight.pilot ) then
			local ac = self.def.aircraft[ flight.aircraft ]
			local spacing = U.FromMeters( start.airborne and 150 or 60 )

			-- На земле самолёты встают друг за другом по полосе, в воздухе строем пеленга
			local pos = basePos - baseAng:Forward() * spacing * (i - 1)

			if start.airborne then
				pos = basePos - baseAng:Forward() * spacing * (i - 1) + baseAng:Right() * spacing * (i - 1)

				if start.alt then
					pos.z = SkyOps.Map.SeaLevel() + U.FromMeters( start.alt )
				end
			end

			local jet = Spawn.PlayerJet( ac.role, pos, baseAng, flight.loadout )

			if IsValid( jet ) then
				spawned = spawned + 1
				flight.jet = jet
				flight.pilotSid = flight.pilot:SteamID()
				jet.SkyOpsFlight = i

				local pilot, wso = flight.pilot, flight.wso
				local airborne = start.airborne == true
				local speed = U.FromMeters( (start.speed or 600) / 3.6 )

				timer.Simple( 0.2, function()
					if not IsValid( jet ) then return end

					-- Старт в воздухе: двигатель запущен, шасси убраны, самолёт уже летит
					if airborne then
						if jet.StartEngine then jet:StartEngine() end
						if jet.SetThrottle then jet:SetThrottle( 1 ) end
						if jet.RaiseLandingGear then jet:RaiseLandingGear() end

						local phys = jet:GetPhysicsObject()

						if IsValid( phys ) then phys:SetVelocity( baseAng:Forward() * speed ) end
					end

					if IsValid( pilot ) and jet.GetDriverSeat and IsValid( jet:GetDriverSeat() ) then
						pilot:ExitVehicle()
						pilot:EnterVehicle( jet:GetDriverSeat() )
					end

					if IsValid( wso ) and jet.GetPassengerSeat then
						local seat = jet:GetPassengerSeat( 2 )

						if IsValid( seat ) then
							wso:ExitVehicle()
							wso:EnterVehicle( seat )
						end
					end
				end )
			end
		end
	end

	if spawned == 0 then
		self:Radio( "SkyOps", "Не удалось создать ни одного самолёта. Установлены ли аддоны самолётов?" )

		return false
	end

	return true
end

function Run:Launch()
	if self.state ~= M.STATE_BRIEFING then return end

	self.launchAt = nil

	if not self:SpawnFlights() then
		-- не вышло: снимаем готовность и ждём, чтобы не повторять попытку каждые полсекунды
		for _, flight in ipairs( self.flights ) do flight.ready = {} end

		self.briefEnds = CurTime() + 30
		self:SendLobby()

		return
	end

	self:SpawnUnits()

	self.state = M.STATE_RUNNING
	self.startTime = CurTime()

	for _, ply in ipairs( self:SeatedPlayers() ) do
		self:Stat( ply )
	end

	self:UpdateObjectives()
	self:SendState()
	self:SendObjectives()

	local radio = self.def.radio and self.def.radio.start or (self:FlightCallsign( 1 ) .. ", вылет разрешён. Удачи.")
	self:Radio( "КП", radio )
end

function Run:OnUnitKilled( ent, attacker )
	local groupId = self.entGroup[ ent ]

	if not groupId then return end

	local group = self.groups[ groupId ]

	if group.dead[ ent ] then return end

	group.dead[ ent ] = true
	group.killed = group.killed + 1

	-- Попадание засчитываем стрелку; если атакующий самолёт, то его пилоту
	if IsValid( attacker ) and not attacker:IsPlayer() and attacker.GetDriver then
		attacker = attacker:GetDriver()
	end

	if IsValid( attacker ) and attacker:IsPlayer() then
		local stat = self:Stat( attacker )

		stat.kills = stat.kills + 1
		stat.killsByGroup[ groupId ] = (stat.killsByGroup[ groupId ] or 0) + 1
	end

	self.totalKills = self.totalKills + 1
end

function Run:IsObjectiveDone( id )
	for _, obj in ipairs( self.objectives ) do
		if obj.def.id == id then return obj.state == M.OBJ_DONE end
	end

	return false
end

function Run:SetObjectiveState( obj, state )
	if obj.state == state then return end

	obj.state = state

	hook.Run( "SkyOps.ObjectiveChanged", obj, self )

	if state == M.OBJ_DONE then
		self:Radio( "КП", obj.def.radio or ("Задача выполнена: " .. obj.def.text) )
	elseif state == M.OBJ_FAILED then
		self:Radio( "КП", "Задача провалена: " .. obj.def.text )
	end
end

function Run:UpdateObjectives()
	local changed = false

	for _, obj in ipairs( self.objectives ) do
		local before = obj.state .. "|" .. tostring( obj.progressText )

		if obj.state == M.OBJ_PENDING and (not obj.def.after or self:IsObjectiveDone( obj.def.after )) then
			self:SetObjectiveState( obj, M.OBJ_ACTIVE )
		end

		if obj.state == M.OBJ_ACTIVE then
			local check = SkyOps.Objectives.Check[ obj.def.type ]
			local result = check and check( self, obj )

			if result == "done" then
				self:SetObjectiveState( obj, M.OBJ_DONE )
			elseif result == "failed" then
				self:SetObjectiveState( obj, M.OBJ_FAILED )
			end
		end

		if before ~= obj.state .. "|" .. tostring( obj.progressText ) then changed = true end
	end

	if changed then self:SendObjectives() end
end

function Run:CheckEnd()
	local success = true
	local reason

	for _, obj in ipairs( self.objectives ) do
		if not obj.def.optional then
			if obj.state == M.OBJ_FAILED then
				return false, "Провалена задача: " .. obj.def.text
			end

			if obj.state ~= M.OBJ_DONE and not SkyOps.Objectives.CompleteOnSuccess[ obj.def.type ] then
				success = false
			end
		end
	end

	if success then return true end

	local fail = self.def.fail or {}

	if fail.crew_dead ~= false and #self:Jets() == 0 then
		reason = "Все экипажи потеряны"

		return false, reason
	end

	if fail.time_limit and CurTime() - self.startTime > fail.time_limit then
		return false, "Вышло время"
	end
end

function Run:Finish( success, reason )
	if self.state == M.STATE_DEBRIEF then return end

	if success then
		for _, obj in ipairs( self.objectives ) do
			if obj.state ~= M.OBJ_FAILED and SkyOps.Objectives.CompleteOnSuccess[ obj.def.type ] then
				obj.state = M.OBJ_DONE
			end
		end
	end

	self.state = M.STATE_DEBRIEF

	-- Очки и оценка
	local score = 0
	local scoreDef = self.def.score or {}

	for _, obj in ipairs( self.objectives ) do
		if obj.state == M.OBJ_DONE then score = score + (scoreDef[ obj.def.id ] or 0) end
	end

	score = score + (scoreDef.per_kill or 0) * self.totalKills

	local grade = "D"

	if success then
		for _, g in ipairs( { "S", "A", "B", "C" } ) do
			if scoreDef.grades and scoreDef.grades[ g ] and score >= scoreDef.grades[ g ] then
				grade = g

				break
			end
		end
	end

	local debrief = {
		id = self.def.id,
		name = self.def.name,
		success = success,
		reason = reason,
		time = CurTime() - (self.startTime or CurTime()),
		score = score,
		grade = grade,
		objectives = {},
		flights = {},
	}

	for _, obj in ipairs( self.objectives ) do
		table.insert( debrief.objectives, { text = obj.def.text, state = obj.state, optional = obj.def.optional == true, progressText = obj.progressText } )
	end

	for i, flight in ipairs( self.flights ) do
		if flight.pilotSid or IsValid( flight.pilot ) then
			local ac = self.def.aircraft[ flight.aircraft ]
			local entry = { callsign = self:FlightCallsign( i ), role = ac.role, crew = {} }

			for _, member in ipairs( { { flight.pilot, "pilot" }, { flight.wso, "wso" } } ) do
				local ply = member[1]

				if IsValid( ply ) then
					local stat = self:Stat( ply )

					table.insert( entry.crew, { seat = member[2], name = stat.name, kills = stat.kills } )
				end
			end

			if IsValid( flight.jet ) and flight.jet.GetHP and flight.jet.GetMaxHP then
				entry.hp = flight.jet:GetHP() / math.max( flight.jet:GetMaxHP(), 1 )
			else
				entry.hp = 0
			end

			table.insert( debrief.flights, entry )
		end
	end

	self.debrief = debrief

	SendTable( "skyops_debrief", debrief )
	self:SendState()

	hook.Run( "SkyOps.MissionEnd", debrief, self )
end

function Run:Think()
	if self.state == M.STATE_BRIEFING then
		local T = CurTime()

		if self.launchAt and T >= self.launchAt then
			self:Launch()
		elseif T >= self.briefEnds then
			if #self:SeatedPlayers() > 0 then
				self:Launch()
			else
				-- никто не сел: ждём дальше
				self.briefEnds = T + 30
				self:SendLobby()
			end
		end

		return
	end

	if self.state == M.STATE_RUNNING then
		self:UpdateObjectives()

		local finished, reason = self:CheckEnd()

		if finished ~= nil then
			self:Finish( finished, reason )
		end
	end
end

function Run:Cleanup()
	self.cleaning = true

	for _, group in pairs( self.groups ) do
		for _, ent in ipairs( group.ents ) do
			if IsValid( ent ) then ent:Remove() end
		end
	end

	for _, flight in ipairs( self.flights ) do
		if IsValid( flight.jet ) then flight.jet:Remove() end
	end
end

-- Публичный API
function M.GetActive()
	return M.Active
end

function M.Start( id )
	local def = M.Get( id )

	if not def then return false, "нет миссии " .. tostring( id ) end

	if M.Active then
		M.Active:Cleanup()
	end

	local run = setmetatable( {
		def = def,
		state = M.STATE_BRIEFING,
		flights = {},
		groups = {},
		entGroup = {},
		stats = {},
		sites = {},
		unitSite = {},
		objectives = {},
		waypoints = {},
		totalKills = 0,
		briefEnds = CurTime() + (def.brief_time or cvBriefTime:GetFloat()),
	}, Run )

	for i = 1, def.flights do
		run.flights[ i ] = { aircraft = 1, loadout = M.DefaultLoadout( def.aircraft[1] ), ready = {} }
	end

	for _, wp in ipairs( def.waypoints or {} ) do
		local pos = SkyOps.Map.Anchor( wp.anchor )

		if pos then
			run.waypoints[ wp.id ] = { pos = pos, radius = wp.radius or 1500 }
		else
			ErrorNoHalt( "[SkyOps] " .. def.id .. ": нет якоря " .. tostring( wp.anchor ) .. " для " .. wp.id .. "\n" )
		end
	end

	for _, objDef in ipairs( def.objectives ) do
		table.insert( run.objectives, { def = objDef, state = M.OBJ_PENDING } )
	end

	run:ResolveUnitPositions()
	run.brief = run:BuildBrief()

	M.Active = run

	run:SendState()
	run:SendBrief()
	run:SendLobby()

	if #run.todoAnchors > 0 then
		print( "[SkyOps] Внимание: якоря с примерными координатами: " .. table.concat( run.todoAnchors, ", " ) )
	end

	hook.Run( "SkyOps.MissionStart", def, run )

	return true
end

function M.Abort()
	if not M.Active then return end

	M.Active:Cleanup()
	M.Active.state = M.STATE_IDLE
	M.Active:SendState()
	M.Active = nil
end

local function SendList( target )
	local list = {}

	for id, def in pairs( M.List ) do
		table.insert( list, { id = id, name = def.name, type = def.type, typeName = M.ObjectiveTypeName[ def.type ] } )
	end

	table.SortByMember( list, "id", true )

	SendTable( "skyops_list", list, target )
end

timer.Create( "skyops_mission_think", SkyOps.Objectives and SkyOps.Objectives.TICK or 0.5, 0, function()
	if M.Active then M.Active:Think() end
end )

hook.Add( "SkyOps.AirDefenseReady", "skyops_mission", function( main, parts, groupId )
	if M.Active and M.Active.state == M.STATE_RUNNING and istable( parts ) then
		M.Active:OnAirDefenseReady( main, parts )
	end
end )

hook.Add( "SkyOps.UnitKilled", "skyops_mission", function( ent, groupId, attacker )
	if M.Active and M.Active.state == M.STATE_RUNNING then
		M.Active:OnUnitKilled( ent, attacker )
	end
end )

-- Запасной учёт: если ядро не вызвало хук, удаление юнита во время миссии считаем уничтожением
hook.Add( "EntityRemoved", "skyops_mission", function( ent )
	local run = M.Active

	if not run or run.cleaning or run.state ~= M.STATE_RUNNING then return end

	if run.entGroup[ ent ] then
		run:OnUnitKilled( ent, nil )
	end
end )

hook.Add( "PlayerDisconnected", "skyops_mission", function( ply )
	local run = M.Active

	if run and run.state == M.STATE_BRIEFING then
		run:LeaveSeat( ply )
		run:SendLobby()
	end
end )

net.Receive( "skyops_slot", function( len, ply )
	local run = M.Active

	if not run then return end

	local index = net.ReadUInt( 4 )
	local seat = net.ReadUInt( 2 )
	local aircraft = net.ReadUInt( 4 )

	if index == 0 then
		run:LeaveSeat( ply )
		run:SendLobby()

		return
	end

	run:TakeSeat( ply, index, seat, aircraft > 0 and aircraft or nil )
end )

net.Receive( "skyops_loadout", function( len, ply )
	local run = M.Active

	if not run or run.state ~= M.STATE_BRIEFING then return end

	local index = net.ReadUInt( 4 )
	local id = net.ReadUInt( 8 )
	local flight = run.flights[ index ]

	-- подвеску выбирает пилот своего звена
	if not flight or flight.pilot ~= ply then return end
	if not M.IsLoadoutAllowed( run.def.aircraft[ flight.aircraft ], id ) then return end

	flight.loadout = id
	run:SendLobby()
end )

net.Receive( "skyops_ready", function( len, ply )
	local run = M.Active

	if not run or run.state ~= M.STATE_BRIEFING then return end

	run:SetReady( ply, net.ReadBool() )
end )

net.Receive( "skyops_sync", function( len, ply )
	if (ply.SkyOpsNextSync or 0) > CurTime() then return end

	ply.SkyOpsNextSync = CurTime() + 2

	SendList( ply )

	local run = M.Active

	if not run then return end

	run:SendState( ply )
	run:SendBrief( ply )

	if run.state == M.STATE_BRIEFING then
		run:SendLobby( ply )
	elseif run.state == M.STATE_RUNNING then
		run:SendObjectives( ply )
	elseif run.state == M.STATE_DEBRIEF and run.debrief then
		SendTable( "skyops_debrief", run.debrief, ply )
	end
end )

-- Команды администратора
concommand.Add( "skyops_mission_start", function( ply, cmd, args )
	if not IsAdmin( ply ) then return end

	local ok, err = M.Start( args[1] )

	if not ok then
		local text = "[SkyOps] " .. err

		if IsValid( ply ) then ply:ChatPrint( text ) else print( text ) end
	end
end, function( cmd, argStr )
	local out = {}

	for id in pairs( M.List ) do
		table.insert( out, cmd .. " " .. id )
	end

	return out
end )

concommand.Add( "skyops_mission_restart", function( ply )
	if not IsAdmin( ply ) or not M.Active then return end

	M.Start( M.Active.def.id )
end )

concommand.Add( "skyops_mission_launch", function( ply )
	if not IsAdmin( ply ) or not M.Active then return end

	M.Active:Launch()
end )

concommand.Add( "skyops_mission_abort", function( ply )
	if not IsAdmin( ply ) then return end

	M.Abort()
end )

concommand.Add( "skyops_mission_list", function( ply )
	if IsValid( ply ) then
		SendList( ply )
	else
		for id, def in pairs( M.List ) do
			print( id .. "  " .. def.name )
		end
	end
end )
