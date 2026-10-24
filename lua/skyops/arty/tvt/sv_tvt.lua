-- Артиллерия, команда на команду (skyops_tvt 1), сервер: выбор команды, метка команды
-- на технике и запрет садиться в чужую технику. Кто что видит, решают сами модули через
-- SkyOps.Teams (core/sh_teams.lua): Friendly, CanSee, Recipients.
--
-- Команда игрока: !синие / !красные / !команда в чате, skyops_team 1|2|auto в консоли.
-- Технику (2С35, дрон с пультом, КамАЗ, катапульту, ящик) метит:
--  * спавн из меню спавна или из наших модулей (создатель = игрок с командой);
--  * посадка в технику без команды;
-- !комплект — выдать своей команде 2С35 и КамАЗ (в кузове дроны) рядом с игроком.

local T = SkyOps.Teams

local cvLock = CreateConVar( "skyops_tvt_lock", "1", FCVAR_ARCHIVE, "Команда на команду: 1 = нельзя садиться в чужую технику и брать чужой пульт дрона", 0, 1 )
local cvKit = CreateConVar( "skyops_tvt_kit", "1", FCVAR_ARCHIVE, "Команда на команду: 1 = игроки могут выдать себе комплект !комплект (2С35 + КамАЗ)", 0, 1 )

local KIT_COOLDOWN = 60

-- классы, которые получают команду (у LVS-техники флаг ENT.LVS)
local TAGGED = {
	sw_uav_control = true,
	sw_uav_catapult = true,
	skyops_arty_ammocrate = true,
}

local function Tell( ply, msg )
	if IsValid( ply ) then ply:ChatPrint( "[Команды] " .. msg ) end
end

local function TellAll( msg )
	for _, ply in ipairs( player.GetAll() ) do ply:ChatPrint( "[Команды] " .. msg ) end
end

local function Taggable( ent )
	return IsValid( ent ) and not ent:IsPlayer() and ( ent.LVS or TAGGED[ ent:GetClass() ] ) and true or false
end

-- корпус техники для кресла (LVS-под) или сама сущность
local function Base( ent )
	if not IsValid( ent ) then return nil end

	if ent.lvsGetVehicle then
		local v = ent:lvsGetVehicle()

		if IsValid( v ) then return v end
	end

	local p = ent:GetParent()

	return IsValid( p ) and p or ent
end

-- пометить технику командой игрока, если у неё ещё нет команды
function T.Claim( ent, ply )
	local team = T.Of( ply )

	if team == 0 or not Taggable( ent ) or ent:GetNW2Int( T.NW, 0 ) ~= 0 then return end

	T.Set( ent, team )

	-- ИИ и интерфейс LVS тоже различают стороны
	if isfunction( ent.SetAITEAM ) and T.TvT() then ent:SetAITEAM( team ) end
end

local function Count( team )
	local n = 0

	for _, ply in ipairs( player.GetAll() ) do
		if T.Of( ply ) == team then n = n + 1 end
	end

	return n
end

local function Smaller()
	return Count( T.RED ) < Count( T.BLUE ) and T.RED or T.BLUE
end

function T.Join( ply, team, quiet )
	if not IsValid( ply ) then return end

	if team ~= T.BLUE and team ~= T.RED then team = Smaller() end

	local old = T.Of( ply )

	ply:SetNW2Int( T.NW, team )

	if ply.lvsSetAITeam then ply:lvsSetAITeam( team ) end

	if old ~= team then
		-- запомненные САУ и дрон могли остаться у другой команды
		local drone = ply:GetNW2Entity( "SkyOpsArty_Drone" )

		if IsValid( drone ) and not T.Friendly( ply, drone ) then ply:SetNW2Entity( "SkyOpsArty_Drone", NULL ) end
		if IsValid( ply.SkyOpsArty_SPG ) and not T.Friendly( ply, ply.SkyOpsArty_SPG ) then
			ply.SkyOpsArty_SPG, ply.SkyOpsArty_SPGPod = nil, nil
		end

		-- задание другой команды игрок покидает
		local M = SkyOps.Arty.Missions

		if M and M.Run and M.Run.players[ ply ] and M.Leave then M.Leave( ply ) end
	end

	if not quiet then TellAll( ply:Nick() .. " играет за команду «" .. T.Name( team ) .. "»" ) end

	hook.Run( "SkyOps.TeamChanged", ply, team, old )
end

local function AssignAll()
	for _, ply in ipairs( player.GetAll() ) do
		if T.Of( ply ) == 0 then T.Join( ply, nil, true ) end
	end

	for _, ply in ipairs( player.GetAll() ) do
		Tell( ply, "Режим команда на команду. Ты за «" .. T.Name( T.Of( ply ) ) .. "». Сменить: !синие или !красные, своя техника: !комплект" )
	end
end

cvars.AddChangeCallback( "skyops_tvt", function( _, _, new )
	if tonumber( new ) == 1 then
		AssignAll()
	else
		TellAll( "Режим команда на команду выключен: все видят всё" )
	end
end, "SkyOps.TvT" )

hook.Add( "PlayerInitialSpawn", "SkyOps.TvT", function( ply )
	timer.Simple( 3, function()
		if not IsValid( ply ) or not T.TvT() or T.Of( ply ) ~= 0 then return end

		T.Join( ply, nil, true )
		Tell( ply, "Режим команда на команду. Ты за «" .. T.Name( T.Of( ply ) ) .. "». Сменить: !синие или !красные, своя техника: !комплект" )
	end )
end )

-- Метки на технике ------------------------------------------------------------------------

hook.Add( "PlayerSpawnedSENT", "SkyOps.TvT", function( ply, ent ) T.Claim( ent, ply ) end )
hook.Add( "PlayerSpawnedVehicle", "SkyOps.TvT", function( ply, ent ) T.Claim( ent, ply ) end )

-- техника из наших модулей (вылет дрона, катапульта КамАЗа, комплект задания) ставит
-- создателя через SetCreator / CPPISetOwner; пульт дрона берёт команду дрона сам (T.Of)
hook.Add( "OnEntityCreated", "SkyOps.TvT", function( ent )
	timer.Simple( 0, function()
		if not Taggable( ent ) or ent:GetNW2Int( T.NW, 0 ) ~= 0 then return end

		local owner = ent.GetCreator and ent:GetCreator()

		if not IsValid( owner ) and ent.CPPIGetOwner then owner = ent:CPPIGetOwner() end
		if IsValid( owner ) and owner:IsPlayer() then T.Claim( ent, owner ) end
	end )
end )

hook.Add( "PlayerEnteredVehicle", "SkyOps.TvT", function( ply, pod )
	if T.TvT() then T.Claim( Base( pod ), ply ) end
end )

-- Чужая техника ---------------------------------------------------------------------------

local function Enemy( ply, ent )
	return T.TvT() and cvLock:GetBool() and not T.Friendly( ply, Base( ent ) )
end

local function Refuse( ply )
	if ( ply.SkyOps_NextRefuse or 0 ) > CurTime() then return end

	ply.SkyOps_NextRefuse = CurTime() + 2
	ply:PrintMessage( HUD_PRINTCENTER, "Это техника другой команды" )
end

hook.Add( "CanPlayerEnterVehicle", "SkyOps.TvT", function( ply, pod )
	if Enemy( ply, pod ) then
		Refuse( ply )
		return false
	end
end )

hook.Add( "PlayerUse", "SkyOps.TvT", function( ply, ent )
	if Taggable( Base( ent ) ) and Enemy( ply, ent ) then
		Refuse( ply )
		return false
	end
end )

-- Комплект команды ------------------------------------------------------------------------

local function TruckClass()
	local S = SkyOps.Arty.Supply
	local list = S and S.cvCarriers and string.Explode( ",", S.cvCarriers:GetString() ) or { "sw_kamaz5350" }

	for _, c in ipairs( list ) do
		c = string.Trim( c )

		if c ~= "" and scripted_ents.GetStored( c ) then return c end
	end

	return S and S.CRATE_CLASS or nil
end

local function SpawnFor( ply, class, pos, ang )
	if not class or not scripted_ents.GetStored( class ) then return nil end

	local ent = ents.Create( class )

	if not IsValid( ent ) then return nil end

	ent:SetPos( pos )
	ent:SetAngles( ang )
	ent:Spawn()
	ent:Activate()

	if ent.CPPISetOwner then ent:CPPISetOwner( ply ) end
	if ent.SetCreator then ent:SetCreator( ply ) end

	T.Claim( ent, ply )

	undo.Create( "SkyOps kit" )
	undo.AddEntity( ent )
	undo.SetPlayer( ply )
	undo.Finish()

	return ent
end

-- точка на земле перед игроком: f вперёд, r вправо, метры
local function Spot( ply, f, r )
	local upm = SkyOps.Arty.Grid and SkyOps.Arty.Grid.UPM() or 52.49
	local yaw = Angle( 0, ply:EyeAngles().y, 0 )
	local p = ply:GetPos() + yaw:Forward() * f * upm + yaw:Right() * r * upm
	local tr = util.TraceLine( { start = p + Vector( 0, 0, 2000 ), endpos = p - Vector( 0, 0, 4000 ), mask = MASK_SOLID_BRUSHONLY } )

	return ( tr.Hit and tr.HitPos or p ) + Vector( 0, 0, 60 ), yaw
end

function T.GiveKit( ply )
	if not cvKit:GetBool() and not ply:IsAdmin() then return Tell( ply, "Комплект выключен (skyops_tvt_kit 0)" ) end
	if T.Of( ply ) == 0 then return Tell( ply, "Сначала выбери команду: !синие или !красные" ) end
	if ( ply.SkyOps_NextKit or 0 ) > CurTime() then
		return Tell( ply, string.format( "Комплект можно взять через %d с", math.ceil( ply.SkyOps_NextKit - CurTime() ) ) )
	end

	local pos, yaw = Spot( ply, 14, 0 )
	local spg = SpawnFor( ply, "sw_2s35", pos, yaw )

	pos = Spot( ply, 0, 16 )

	local truck = SpawnFor( ply, TruckClass(), pos, yaw )

	if not spg and not truck then return Tell( ply, "Не удалось создать технику: нет аддонов 2С35 и КамАЗа" ) end

	ply.SkyOps_NextKit = CurTime() + KIT_COOLDOWN

	local got = {}

	if spg then got[ #got + 1 ] = "2С35 впереди" end
	if truck then got[ #got + 1 ] = ( truck:GetClass() == "skyops_arty_ammocrate" and "ящик БК" or "КамАЗ с дронами" ) .. " справа" end

	Tell( ply, "Комплект команды «" .. T.Name( T.Of( ply ) ) .. "»: " .. table.concat( got, ", " ) )
end

-- Команды ---------------------------------------------------------------------------------

local NAMES = {
	[ "1" ] = T.BLUE, blue = T.BLUE, [ "синие" ] = T.BLUE, [ "синий" ] = T.BLUE,
	[ "2" ] = T.RED, red = T.RED, [ "красные" ] = T.RED, [ "красный" ] = T.RED,
}

-- string.lower не трогает кириллицу: «!Синие» -> «!синие» вручную (UTF-8, А-Я и Ё)
local function Lower( s )
	s = string.gsub( s, "\208([\144-\175])", function( c )
		local b = string.byte( c )

		return b < 160 and "\208" .. string.char( b + 32 ) or "\209" .. string.char( b - 32 )
	end )

	return string.lower( ( string.gsub( s, "\208\129", "\209\145" ) ) )
end

local function Pick( ply, arg )
	if not IsValid( ply ) then return end

	local team = NAMES[ Lower( arg or "" ) ]

	if not team and arg ~= "auto" then
		return Tell( ply, "Ты за «" .. T.Name( T.Of( ply ) ) .. "». Выбор: !синие, !красные" .. ( T.TvT() and "" or ". Режим выключен, включить: skyops_tvt 1" ) )
	end

	if ( ply.SkyOps_NextTeam or 0 ) > CurTime() then return Tell( ply, "Подожди пару секунд" ) end

	ply.SkyOps_NextTeam = CurTime() + 3

	T.Join( ply, team )
end

concommand.Add( "skyops_team", function( ply, _, args ) Pick( ply, args[ 1 ] ) end,
	function( cmd ) return { cmd .. " 1", cmd .. " 2", cmd .. " auto" } end,
	"Команда на команду: выбрать команду 1 (синие), 2 (красные) или auto" )

concommand.Add( "skyops_team_kit", function( ply ) if IsValid( ply ) then T.GiveKit( ply ) end end, nil,
	"Команда на команду: выдать своей команде 2С35 и КамАЗ рядом с игроком" )

hook.Add( "PlayerSay", "SkyOps.TvT", function( ply, text )
	local t = Lower( string.Trim( text ) )

	if t == "!синие" or t == "!blue" then Pick( ply, "1" ) return "" end
	if t == "!красные" or t == "!red" then Pick( ply, "2" ) return "" end
	if t == "!комплект" or t == "!kit" then T.GiveKit( ply ) return "" end

	local arg = string.match( t, "^!команда%s*(.*)$" ) or string.match( t, "^!team%s*(.*)$" )

	if arg then
		if arg == "" then ply:ConCommand( "skyops_team_menu" ) else Pick( ply, arg ) end
		return ""
	end
end )

-- после перезагрузки Lua игроки без команды в уже включённом режиме
if T.TvT() then
	timer.Simple( 1, function()
		for _, ply in ipairs( player.GetAll() ) do
			if T.Of( ply ) == 0 then T.Join( ply, nil, true ) end
		end
	end )
end
