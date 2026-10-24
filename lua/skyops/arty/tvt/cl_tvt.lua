-- Артиллерия, команда на команду, клиент: плашка своей команды в правом верхнем углу и
-- меню выбора команды (skyops_team_menu). Фильтрация меток — в модулях через SkyOps.Teams.

local T = SkyOps.Teams

local cvShow = CreateClientConVar( "skyops_tvt_hud", "1", true, false, "Команда на команду: показывать плашку своей команды" )

surface.CreateFont( "SkyOps_TvT", { font = "Roboto", size = 18, weight = 700, extended = true } )

hook.Add( "HUDPaint", "SkyOps.TvT", function()
	if not T.TvT() or not cvShow:GetBool() then return end

	local ply = LocalPlayer()

	if not IsValid( ply ) then return end

	local team = T.Of( ply )
	local text = team ~= 0 and ( "Команда: " .. T.Name( team ) ) or "Без команды: !синие или !красные"
	local col = T.COLORS[ team ] or Color( 220, 220, 220 )

	surface.SetFont( "SkyOps_TvT" )

	local w, h = surface.GetTextSize( text )
	local x, y = ScrW() - w - 24, 8

	draw.RoundedBox( 4, x - 8, y - 3, w + 16, h + 6, Color( 0, 0, 0, 160 ) )
	draw.SimpleText( text, "SkyOps_TvT", x, y, col )
end )

concommand.Add( "skyops_team_menu", function()
	local f = vgui.Create( "DFrame" )

	f:SetTitle( "Команда" )
	f:SetSize( 320, 150 )
	f:Center()
	f:MakePopup()

	for i, team in ipairs( { T.BLUE, T.RED } ) do
		local b = vgui.Create( "DButton", f )

		b:SetText( T.Name( team ) )
		b:SetTextColor( T.COLORS[ team ] )
		b:SetFont( "SkyOps_TvT" )
		b:SetPos( 10 + ( i - 1 ) * 155, 34 )
		b:SetSize( 145, 50 )
		b.DoClick = function()
			RunConsoleCommand( "skyops_team", tostring( team ) )
			f:Close()
		end
	end

	local kit = vgui.Create( "DButton", f )

	kit:SetText( "Выдать комплект: 2С35 + КамАЗ" )
	kit:SetPos( 10, 94 )
	kit:SetSize( 300, 44 )
	kit.DoClick = function()
		RunConsoleCommand( "skyops_team_kit" )
		f:Close()
	end
end, nil, "Команда на команду: меню выбора команды" )
