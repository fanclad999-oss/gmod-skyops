-- Artillery supply, HUD: the load by shell type in the 2S35 (top left) and the stock in
-- the supply carrier. Draws with the arty UI style (arty/ui/cl_base), loaded after us.

local S = SkyOps.Arty.Supply

local cvShow = CreateClientConVar( "skyops_arty_ui_ammo", "1", true, false, "Боекомплект САУ и груз машины снабжения на экране" )

local function MyVehicle()
	local ply = LocalPlayer()
	local veh = IsValid( ply ) and ply.lvsGetVehicle and ply:lvsGetVehicle()

	return IsValid( veh ) and veh or nil
end

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

	Panel( UI, rows, string.format( "СНАБЖЕНИЕ: %d выстр.", stock ), stock > 0 and C.accent or C.threat )
end

hook.Add( "HUDPaint", "SkyOpsArty.Supply", function()
	local UI = SkyOps.Arty.UI

	if not cvShow:GetBool() or not S.Enabled() or not UI or not UI.C or IsValid( UI.TabletFrame ) then return end

	local veh = MyVehicle()

	if not veh then return end

	if SkyOps.Arty.SPG and SkyOps.Arty.SPG.IsSPG( veh ) then
		PaintGun( UI, veh )
	elseif S.IsCarrier( veh ) then
		PaintCarrier( UI, veh )
	end
end )
