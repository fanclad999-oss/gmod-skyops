-- Artillery supply, HUD: the load by shell type in the 2S35 (top left), the stock in the
-- supply carrier and the drone kit key at the truck. Draws with the arty UI style
-- (arty/ui/cl_base), loaded after us.

local S = SkyOps.Arty.Supply

local cvShow = CreateClientConVar( "skyops_arty_ui_ammo", "1", true, false, "Боекомплект САУ и груз машины снабжения на экране" )
local cvKitKey = CreateClientConVar( "skyops_arty_key_kit", tostring( KEY_O ), true, false, "КамАЗ: выгрузить / убрать катапульту с дроном (номер KEY_*)" )

local function MyVehicle()
	local ply = LocalPlayer()
	local veh = IsValid( ply ) and ply.lvsGetVehicle and ply:lvsGetVehicle()

	return IsValid( veh ) and veh or nil
end

local function IsTruck( ent )
	return S.IsCarrier( ent ) and ent:GetClass() ~= S.CRATE_CLASS
end

-- the truck the kit key works on: the one we drive, or the nearest on foot
local function KitTruck()
	local ply = LocalPlayer()
	local veh = MyVehicle()

	if veh then return IsTruck( veh ) and veh or nil end
	if not IsValid( ply ) or ply:InVehicle() then return nil end

	local best, bestD = nil, S.KIT_RANGE * ( SkyOps.Arty.Grid and SkyOps.Arty.Grid.UPM() or 40 )

	for _, ent in ipairs( ents.GetAll() ) do
		if IsTruck( ent ) and SkyOps.Teams.CanSee( ply, ent ) then
			local d = ent:GetPos():Distance( ply:GetPos() )

			if d < bestD then best, bestD = ent, d end
		end
	end

	return best
end

local function KitKeyName()
	return string.upper( input.GetKeyName( cvKitKey:GetInt() ) or "?" )
end

local function KitHint( truck )
	if truck:GetNW2Bool( "SkyOpsArty_KitOut", false ) then return "[" .. KitKeyName() .. "] убрать катапульту и дрон" end
	if truck:GetNW2Int( "SkyOpsArty_KitDrones", 0 ) > 0 then return "[" .. KitKeyName() .. "] выгрузить катапульту с дроном" end

	return "[" .. KitKeyName() .. "] выгрузить катапульту (дронов нет)"
end

-- polled: PlayerButtonDown does not run on the client in single player
local kitDown = false

hook.Add( "Think", "SkyOpsArty.Supply.Kit", function()
	local key = cvKitKey:GetInt()
	local down = key > 0 and input.IsKeyDown( key )

	if down and not kitDown and not vgui.GetKeyboardFocus() and not gui.IsGameUIVisible() and not gui.IsConsoleVisible()
		and not ( LocalPlayer().IsTyping and LocalPlayer():IsTyping() ) and KitTruck() then
		RunConsoleCommand( "skyops_arty_kit" )
	end

	kitDown = down
end )

local function Panel( UI, rows, title, titleCol )
	local C = UI.C
	local x, y = UI.S( 24 ), UI.S( 24 )
	local w, rh = UI.S( 250 ), UI.S( 24 )
	local h = ( #rows + 1 ) * rh + UI.S( 12 )

	UI.Box( x, y, w, h, C.panelAlpha )
	UI.HText( title, "SkyOpsArty_HUDSmall", x + UI.S( 12 ), y + UI.S( 6 ) + rh / 2, titleCol or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )

	for i, r in ipairs( rows ) do
		local ry = y + UI.S( 6 ) + i * rh + rh / 2

		UI.HText( r[ 1 ], "SkyOpsArty_HUDSmall", x + UI.S( 12 ), ry, r[ 3 ] or C.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER )
		UI.HText( r[ 2 ], "SkyOpsArty_HUD", x + w - UI.S( 12 ), ry, r[ 3 ] or C.hud, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER )
	end
end

local function PaintGun( UI, spg )
	local C = UI.C
	local loaded = S.LoadedShell( spg )
	local rows = {}

	for _, id in ipairs( S.Shells() ) do
		local n, want = S.Count( spg, id ), S.Ordered( spg, id )

		if n > 0 or want > 0 or id == loaded then
			local col = n <= 0 and C.threat or id == loaded and C.accent or nil

			rows[ #rows + 1 ] = { ( id == loaded and "> " or "  " ) .. S.ShellName( id ), string.format( "%d/%d", n, want ), col }
		end
	end

	local carrier = spg:GetNW2Entity( "SkyOpsArty_Resupply" )

	if IsValid( carrier ) then
		rows[ #rows + 1 ] = { "ПОДВОЗ", string.format( "в кузове %d", carrier:GetNW2Int( "SkyOpsArty_Stock", 0 ) ), C.ok }
	end

	Panel( UI, rows, string.format( "БОЕКОМПЛЕКТ %d/%d", S.Total( spg ), S.Capacity() ) )
end

local function PaintCarrier( UI, carrier )
	local C = UI.C
	local stock = carrier:GetNW2Int( "SkyOpsArty_Stock", 0 )
	local spg = carrier:GetNW2Entity( "SkyOpsArty_Supplying" )
	local rows = {}

	if IsValid( spg ) then
		rows[ #rows + 1 ] = { "2С35", string.format( "%d/%d", S.Total( spg ), S.Capacity() ), C.ok }
		rows[ #rows + 1 ] = { "ИДЁТ ПОДАЧА", "стоять", C.ok }
	elseif stock > 0 then
		rows[ #rows + 1 ] = { string.format( "к САУ ближе %d м", S.RANGE ), "стоп", C.muted }
	end

	rows[ #rows + 1 ] = { "ДРОНЫ", tostring( carrier:GetNW2Int( "SkyOpsArty_KitDrones", 0 ) ) .. ( carrier:GetNW2Bool( "SkyOpsArty_KitOut", false ) and " + 1 снаружи" or "" ) }

	Panel( UI, rows, string.format( "СНАБЖЕНИЕ: %d выстр.", stock ), stock > 0 and C.accent or C.threat )

	if IsTruck( carrier ) then
		UI.HText( KitHint( carrier ), "SkyOpsArty_HUDSmall", ScrW() / 2, ScrH() - UI.S( 60 ), C.muted, TEXT_ALIGN_CENTER )
	end
end

hook.Add( "HUDPaint", "SkyOpsArty.Supply", function()
	local UI = SkyOps.Arty.UI

	if not cvShow:GetBool() or not UI or not UI.C or IsValid( UI.TabletFrame ) then return end

	local veh = MyVehicle()

	if not veh then
		local truck = KitTruck()

		if truck then UI.HText( KitHint( truck ), "SkyOpsArty_HUDSmall", ScrW() / 2, ScrH() * 0.6, UI.C.text, TEXT_ALIGN_CENTER ) end

		return
	end

	if SkyOps.Arty.SPG and SkyOps.Arty.SPG.IsSPG( veh ) then
		if S.Enabled() then PaintGun( UI, veh ) end
	elseif S.IsCarrier( veh ) then
		PaintCarrier( UI, veh )
	end
end )
