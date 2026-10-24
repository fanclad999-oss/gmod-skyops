-- Artillery supply, server part: counts rounds by shell type in each 2S35, refuses a shot
-- of a shell that ran out, and moves rounds from a standing carrier into a standing gun
-- next to it, one round at a time, towards the load the crew ordered.
--
-- Commands (player in a 2S35):
--   skyops_arty_ammo                       print the load
--   skyops_arty_ammo_order he=20 krasnopol=10 ...   the load wanted after resupply
--                                          ("default" = the standard load)
--   skyops_arty_ammo_fill                  admin: fill the gun to the order at once
--   skyops_arty_supply_refill              admin: refill the carrier you sit in or look at

local S = SkyOps.Arty.Supply
local SPG = SkyOps.Arty.SPG
local Grid = SkyOps.Arty.Grid

local cvTruckStock = CreateConVar( "skyops_arty_supply_stock", "80", FCVAR_ARCHIVE, "Rounds in a fresh supply truck", 0, 1000 )
local cvCrateStock = CreateConVar( "skyops_arty_crate_stock", "40", FCVAR_ARCHIVE, "Rounds in a fresh ammo crate", 0, 1000 )
local cvRoundTime = CreateConVar( "skyops_arty_supply_time", "3", FCVAR_ARCHIVE, "Seconds to pass one round from the carrier to the 2S35", 0.1, 60 )

local THINK = 0.25

local function Tell( ply, msg )
	if IsValid( ply ) then ply:ChatPrint( "[БК] " .. msg ) end
end

local function Occupants( veh )
	local list = {}

	for _, ply in ipairs( player.GetAll() ) do
		local v = ply.lvsGetVehicle and ply:lvsGetVehicle()

		if v == veh then list[ #list + 1 ] = ply end
	end

	return list
end

local function TellAll( veh, msg )
	for _, ply in ipairs( Occupants( veh ) ) do Tell( ply, msg ) end
end

local function Alive( ent )
	return IsValid( ent ) and not ( ent.GetHP and ent:GetHP() <= 0 )
end

local function SpeedMS( ent )
	return ent:GetVelocity():Length() / Grid.UPM()
end

-- Load of the gun ----------------------------------------------------------------------

local Guns, Carriers = {}, {}

function S.SetCount( spg, id, n )
	spg:SetNW2Int( "SkyOpsArty_Ammo_" .. id, math.max( math.floor( n ), 0 ) )
end

-- order = { [id] = rounds }; clamped to the capacity in the shell order
function S.SetOrder( spg, order )
	local left = S.Capacity()

	for _, id in ipairs( S.Shells() ) do
		local n = math.Clamp( math.floor( order[ id ] or 0 ), 0, left )

		spg:SetNW2Int( "SkyOpsArty_Order_" .. id, n )
		left = left - n
	end
end

function S.FillToOrder( spg )
	for _, id in ipairs( S.Shells() ) do S.SetCount( spg, id, S.Ordered( spg, id ) ) end
end

local function InitGun( spg )
	if spg.SkyOpsArty_AmmoInit then return end

	spg.SkyOpsArty_AmmoInit = true
	S.SetOrder( spg, S.DefaultLoad() )
	S.FillToOrder( spg )
	Guns[ spg ] = true
end

function S.InitCarrier( ent )
	if ent.SkyOpsArty_StockInit then return end

	ent.SkyOpsArty_StockInit = true
	ent:SetNW2Int( "SkyOpsArty_Stock", ent:GetClass() == S.CRATE_CLASS and cvCrateStock:GetInt() or cvTruckStock:GetInt() )
	Carriers[ ent ] = true
end

function S.TellStock( carrier, ply )
	Tell( ply, string.format( "В кузове %d выстр.", carrier:GetNW2Int( "SkyOpsArty_Stock", 0 ) ) )
end

local function Track( ent )
	if SPG.IsSPG( ent ) then
		InitGun( ent )
	elseif S.IsCarrier( ent ) then
		S.InitCarrier( ent )
	end
end

hook.Add( "OnEntityCreated", "SkyOps.Arty.Supply", function( ent )
	timer.Simple( 0, function()
		if IsValid( ent ) then Track( ent ) end
	end )
end )

for _, ent in ipairs( ents.GetAll() ) do Track( ent ) end

-- The stock cannon keeps its own counter (40 rounds, one pool for every shell). Hold it
-- equal to the rounds of the shell in the breech, so the stock HUD shows them and the
-- stock cannon itself stays silent when they run out.
local function StockCannon( spg )
	local list = spg.WEAPONS and spg.WEAPONS[ SPG.GUNNER_POD ]

	if not list then return end

	for id, w in pairs( list ) do
		if w.Icon == true and isfunction( w.Attack ) then return id, w end
	end
end

local function SyncStock( spg )
	local id, cannon = StockCannon( spg )

	if not cannon then return end

	local n = S.Enabled() and S.Count( spg, S.LoadedShell( spg ) ) or ( cannon.Ammo or 40 )

	cannon._CurAmmo = n

	local handler = spg.GetWeaponHandler and spg:GetWeaponHandler( SPG.GUNNER_POD )

	if IsValid( handler ) and handler.SetNWAmmo and handler:GetSelectedWeapon() == id and handler:GetNWAmmo() ~= n then
		handler:SetNWAmmo( n )
	end
end

-- Shots --------------------------------------------------------------------------------

-- sv_spg asks before every shot (manual and auto) and when the crew flips through shells
hook.Add( "SkyOps.Arty.CanFireShell", "SkyOps.Arty.Supply", function( spg, shellId )
	if not S.Enabled() or not shellId then return end

	if S.Count( spg, shellId ) <= 0 then
		return false, "нет снарядов «" .. S.ShellName( shellId ) .. "», нужен подвоз"
	end
end )

hook.Add( "SkyOps.Arty.SPGFired", "SkyOps.Arty.Supply", function( spg, shell )
	if not S.Enabled() or not IsValid( spg ) then return end

	local id = shell.shell or "he"
	local left = S.Count( spg, id ) - 1

	S.SetCount( spg, id, left )
	SyncStock( spg )

	if left == 0 then
		TellAll( spg, "Снаряды «" .. S.ShellName( id ) .. "» кончились" )
	elseif left == 3 then
		TellAll( spg, "Осталось 3 «" .. S.ShellName( id ) .. "»" )
	end
end )

-- Resupply -----------------------------------------------------------------------------

-- the shell to pass next: the one furthest below the order, nil when the gun is full
local function NextShell( spg )
	if S.Total( spg ) >= S.Capacity() then return nil end

	local best, bestGap

	for _, id in ipairs( S.Shells() ) do
		local gap = S.Ordered( spg, id ) - S.Count( spg, id )

		if gap > 0 and ( not bestGap or gap > bestGap ) then best, bestGap = id, gap end
	end

	return best
end

local function CanPass( carrier, spg )
	if not Alive( carrier ) or not Alive( spg ) then return false end
	if carrier:GetNW2Int( "SkyOpsArty_Stock", 0 ) <= 0 then return false end
	if SpeedMS( carrier ) > S.MAX_SPEED or SpeedMS( spg ) > S.MAX_SPEED then return false end

	return carrier:GetPos():Distance( spg:GetPos() ) <= S.RANGE * Grid.UPM()
end

local function StopPassing( spg, carrier, msg )
	if IsValid( spg ) then
		spg:SetNW2Entity( "SkyOpsArty_Resupply", NULL )
		spg.SkyOpsArty_NextRound = nil
	end

	if IsValid( carrier ) and carrier:GetNW2Entity( "SkyOpsArty_Supplying" ) == spg then
		carrier:SetNW2Entity( "SkyOpsArty_Supplying", NULL )
	end

	if msg then
		TellAll( spg, msg )

		if IsValid( carrier ) then TellAll( carrier, msg ) end
	end
end

local function ResupplyThink( spg )
	local carrier = spg:GetNW2Entity( "SkyOpsArty_Resupply" )

	if IsValid( carrier ) then
		if not CanPass( carrier, spg ) then
			local why = carrier:GetNW2Int( "SkyOpsArty_Stock", 0 ) <= 0 and "Подвоз: кузов пуст" or "Подвоз прерван"

			return StopPassing( spg, carrier, why )
		end
	else
		carrier = nil

		if not NextShell( spg ) then return end

		for c in pairs( Carriers ) do
			if IsValid( c ) and not IsValid( c:GetNW2Entity( "SkyOpsArty_Supplying" ) ) and CanPass( c, spg ) then
				carrier = c
				break
			end
		end

		if not carrier then return end

		spg:SetNW2Entity( "SkyOpsArty_Resupply", carrier )
		carrier:SetNW2Entity( "SkyOpsArty_Supplying", spg )
		spg.SkyOpsArty_NextRound = CurTime() + cvRoundTime:GetFloat()

		local msg = string.format( "Подвоз начат: %d выстр. в кузове, по %.0f с на выстрел", carrier:GetNW2Int( "SkyOpsArty_Stock", 0 ), cvRoundTime:GetFloat() )

		TellAll( spg, msg )
		TellAll( carrier, msg )

		return
	end

	if CurTime() < ( spg.SkyOpsArty_NextRound or 0 ) then return end

	local id = NextShell( spg )

	if not id then return StopPassing( spg, carrier, string.format( "Боекомплект пополнен: %d/%d", S.Total( spg ), S.Capacity() ) ) end

	S.SetCount( spg, id, S.Count( spg, id ) + 1 )
	carrier:SetNW2Int( "SkyOpsArty_Stock", carrier:GetNW2Int( "SkyOpsArty_Stock", 0 ) - 1 )
	SyncStock( spg )
	hook.Run( "SkyOps.Arty.Resupplied", spg, carrier, id )

	spg.SkyOpsArty_NextRound = CurTime() + cvRoundTime:GetFloat()
end

local nextThink = 0

hook.Add( "Think", "SkyOps.Arty.Supply", function()
	if CurTime() < nextThink then return end

	nextThink = CurTime() + THINK

	for c in pairs( Carriers ) do
		if not IsValid( c ) then Carriers[ c ] = nil end
	end

	for spg in pairs( Guns ) do
		if not IsValid( spg ) then
			Guns[ spg ] = nil
		else
			SyncStock( spg )

			if S.Enabled() then
				ResupplyThink( spg )
			elseif IsValid( spg:GetNW2Entity( "SkyOpsArty_Resupply" ) ) then
				StopPassing( spg, spg:GetNW2Entity( "SkyOpsArty_Resupply" ) )
			end
		end
	end
end )

-- Commands -----------------------------------------------------------------------------

local function LoadText( spg )
	local parts = {}

	for _, id in ipairs( S.Shells() ) do
		if S.Count( spg, id ) > 0 or S.Ordered( spg, id ) > 0 then
			parts[ #parts + 1 ] = string.format( "%s %d/%d", S.ShellName( id ), S.Count( spg, id ), S.Ordered( spg, id ) )
		end
	end

	return string.format( "%d/%d: %s", S.Total( spg ), S.Capacity(), table.concat( parts, ", " ) )
end

concommand.Add( "skyops_arty_ammo", function( ply )
	local spg = SPG.Of( ply )

	if not spg then return Tell( ply, "Сядьте в САУ" ) end

	Tell( ply, LoadText( spg ) )
end )

concommand.Add( "skyops_arty_ammo_order", function( ply, _, args )
	local spg = SPG.Of( ply )

	if not spg then return Tell( ply, "Сядьте в САУ" ) end

	local order

	if args[ 1 ] == "default" then
		order = S.DefaultLoad()
	else
		order = {}

		for _, id in ipairs( S.Shells() ) do order[ id ] = S.Ordered( spg, id ) end

		for _, a in ipairs( args ) do
			local id, n = string.match( a, "^(%w+)=(%d+)$" )

			if not id or order[ id ] == nil then
				return Tell( ply, "skyops_arty_ammo_order he=20 krasnopol=10 ... (снаряды: " .. table.concat( S.Shells(), ", " ) .. ") или default" )
			end

			order[ id ] = tonumber( n )
		end
	end

	S.SetOrder( spg, order )
	Tell( ply, "Заявка на подвоз. " .. LoadText( spg ) )
end )

concommand.Add( "skyops_arty_ammo_fill", function( ply )
	if IsValid( ply ) and not ply:IsAdmin() then return end

	local spg = SPG.Of( ply )

	if not spg then return Tell( ply, "Сядьте в САУ" ) end

	S.FillToOrder( spg )
	SyncStock( spg )
	Tell( ply, "Заполнено. " .. LoadText( spg ) )
end )

concommand.Add( "skyops_arty_supply_refill", function( ply )
	if IsValid( ply ) and not ply:IsAdmin() then return end

	local ent = ply.lvsGetVehicle and ply:lvsGetVehicle()

	if not S.IsCarrier( ent ) then ent = ply:GetEyeTrace().Entity end
	if not S.IsCarrier( ent ) then return Tell( ply, "Сядьте в машину снабжения или посмотрите на ящики" ) end

	ent.SkyOpsArty_StockInit = nil
	Carriers[ ent ] = nil
	S.InitCarrier( ent )
	S.TellStock( ent, ply )
end )
