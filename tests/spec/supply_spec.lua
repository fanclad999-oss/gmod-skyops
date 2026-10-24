-- Боекомплект и подвоз (arty/supply): начальная загрузка, расход по типам, запрет выстрела
-- без снарядов, стоковый счётчик пушки, подвоз с машины снабжения и заявка.
-- САУ — та же заглушка LVS-танка, что в spg_spec, только без башни; пушка считает патроны
-- как LVS: _CurAmmo на таблице оружия.

local gm, T = ...

local FILES = { "skyops/arty/supply/sh_supply.lua", "skyops/arty/supply/sv_supply.lua", "skyops/arty/supply/sv_kit.lua", "skyops/arty/core/sv_spg.lua" }

local UPM = 40

local function makeSPG( pos, ply )
	local spg = gm.entity( { class = "sw_2s35", pos = pos, shellType = 0, hp = 1000 } )

	function spg:GetHP() return self.hp end
	function spg:GetShellType() return self.shellType end
	function spg:SetShellType( t ) self.shellType = t end
	function spg:GetDriver() return ply end
	function spg:GetPassenger( pod ) return pod == 2 and ply or nil end
	function spg:GetEngineActive() return false end
	function spg:GetTurretPitch() return 0 end
	function spg:GetTurretYaw() return 0 end
	function spg:AimTurret() end

	local cannon = { Icon = true, Ammo = 40, Delay = 4 }
	local handler = { selected = 2, nwAmmo = 40, nextAttack = 0 }

	function cannon.Attack( h ) h:TakeAmmo( 1 ) end

	function handler:IsValid() return true end
	function handler:GetSelectedWeapon() return self.selected end
	function handler:SelectWeapon( id ) self.selected = id end
	function handler:GetMaxAmmo() return cannon.Ammo end
	function handler:GetAmmo() return cannon._CurAmmo or cannon.Ammo end
	function handler:TakeAmmo( n ) cannon._CurAmmo = math.max( self:GetAmmo() - n, 0 ) self.nwAmmo = cannon._CurAmmo end
	function handler:GetNWAmmo() return self.nwAmmo end
	function handler:SetNWAmmo( n ) self.nwAmmo = n end
	function handler:GetOverheated() return false end
	function handler:CanAttack() return gm.time >= self.nextAttack end
	function handler:SetNextAttack( t ) self.nextAttack = t end
	function handler:GetHeat() return 0 end
	function handler:SetHeat() end

	spg.WEAPONS = { [ 2 ] = { { Icon = "flir" }, cannon } }
	spg.cannon, spg.handler = cannon, handler

	function spg:GetWeaponHandler( pod ) return pod == 2 and handler or nil end

	return spg
end

local function setup()
	gm.reset( "server" )

	_G.KIR = { S = UPM, MeshHeight = function() return 100 * UPM end }

	gm.loadDirs( { "skyops/core/", "skyops/arty/core/", "skyops/arty/supply/" } )

	local A = _G.SkyOps.Arty
	local ply = gm.entity( { class = "player", player = true } )

	gm.players = { ply }

	local spg = makeSPG( A.Grid.FromGrid( 50000, 50000, 100 ), ply )

	function ply:lvsGetVehicle() return self.veh end

	ply.veh = spg

	table.insert( gm.entities, spg )
	_G.hook.Run( "OnEntityCreated", spg )
	gm.think( 2 )

	return A, spg, ply
end

local function addTruck( A, spg, dist )
	local truck = gm.entity( { class = "sw_kamaz5350", pos = spg:GetPos() + Vector( dist * UPM, 0, 0 ), hp = 1000 } )

	function truck:GetHP() return self.hp end
	function truck:OBBMins() return Vector( -150, -50, 0 ) end
	function truck:OBBMaxs() return Vector( 150, 50, 120 ) end
	function truck:LocalToWorld( v ) return self.pos + v end -- курс 0

	table.insert( gm.entities, truck )
	_G.hook.Run( "OnEntityCreated", truck )
	gm.think( 2 )

	return truck
end

-- КамАЗ с набором дрона: катапульта, дрон и пульт создаются через ents.Create
local function kitWorld( A )
	_G.scripted_ents.GetStored = function( c ) return ( c == "sw_uav_catapult" or c == "sw_orlan10" ) and {} or nil end

	gm.entityFactory = function( class )
		local e = gm.entity( { class = class } )

		function e:GetDriver() return _G.NULL end

		if class == "sw_uav_catapult" then
			function e:Mount( d ) self.mounted = d end
		elseif class == "sw_orlan10" then
			local st = gm.entity( { class = "sw_uav_control" } )

			table.insert( gm.entities, st )
			e.station = st
			function e:GetNWEntity( k ) return k == "UAVControl" and self.station or _G.NULL end
			function e:Remove() self.valid = false st.valid = false end
		end

		table.insert( gm.entities, e )

		return e
	end
end

local function kitOf( class )
	for _, e in ipairs( gm.entities ) do
		if e.class == class and e:IsValid() then return e end
	end
end

local function seconds( s ) gm.think( math.ceil( s * 66 ), 1 / 66 ) end

local function teardown() _G.KIR = nil gm.entityFactory = nil end

local ok, why = T.requires( gm, unpack( FILES ) )

T.describe( "Боекомплект и подвоз", function()
	if not ok then return T.it( "файлы на месте", function() T.skip( why ) end ) end

	T.it( "новая САУ получает штатную загрузку на 40 выстрелов", function()
		local A, spg = setup()
		local S = A.Supply

		T.eq( S.Total( spg ), 40 )
		T.eq( S.Count( spg, "he" ), S.Ordered( spg, "he" ) )
		T.ok( S.Count( spg, "krasnopol" ) > 0, "нет Краснополей" )
		T.eq( spg.cannon._CurAmmo, S.Count( spg, "he" ), "стоковый счётчик не равен ОФС" )
		teardown()
	end )

	T.it( "выстрел тратит снаряд своего типа, стоковый счётчик следует за выбранным", function()
		local A, spg = setup()
		local S = A.Supply
		local he, kr = S.Count( spg, "he" ), S.Count( spg, "krasnopol" )

		_G.hook.Run( "SkyOps.Arty.SPGFired", spg, { shell = "krasnopol" } )
		T.eq( S.Count( spg, "krasnopol" ), kr - 1 )
		T.eq( S.Count( spg, "he" ), he )

		spg.shellType = 1 -- стоковая клавиша: Краснополь
		gm.think( 20 )
		T.eq( spg.cannon._CurAmmo, kr - 1 )
		T.eq( spg.handler.nwAmmo, kr - 1 )
		teardown()
	end )

	T.it( "без снарядов выстрел запрещён и хуком, и стоковой пушкой", function()
		local A, spg = setup()
		local S = A.Supply

		S.SetCount( spg, "he", 0 )
		gm.think( 20 )

		local can, reason = _G.hook.Run( "SkyOps.Arty.CanFireShell", spg, "he" )

		T.eq( can, false )
		T.ok( reason and reason:find( "подвоз" ), tostring( reason ) )

		local fired, err = A.SPG.Fire( spg, "he", 1 )

		T.ok( not fired, "выстрел без снарядов" )
		T.eq( err, "нет снарядов" )

		T.eq( ( _G.hook.Run( "SkyOps.Arty.CanFireShell", spg, "krasnopol" ) ), nil, "Краснополь есть, но запрещён" )
		teardown()
	end )

	T.it( "skyops_arty_ammo_limit 0: снаряды бесконечны", function()
		local A, spg = setup()

		A.Supply.SetCount( spg, "he", 0 )
		_G.GetConVar( "skyops_arty_ammo_limit" ):SetInt( 0 )
		gm.think( 20 )
		T.eq( ( _G.hook.Run( "SkyOps.Arty.CanFireShell", spg, "he" ) ), nil )
		T.eq( spg.cannon._CurAmmo, 40 )
		_G.GetConVar( "skyops_arty_ammo_limit" ):SetInt( 1 )
		teardown()
	end )

	T.it( "грузовик в 10 м и стоит: подаёт по снаряду, пока не наберёт заявку", function()
		local A, spg, ply = setup()
		local S = A.Supply

		S.SetCount( spg, "he", 20 )
		S.SetCount( spg, "krasnopol", 2 )

		local missing = S.Capacity() - S.Total( spg )
		local truck = addTruck( A, spg, 10 )
		local stock = truck.nw.SkyOpsArty_Stock

		T.ok( stock > 0, "грузовик пустой" )
		seconds( 1 )
		T.eq( spg.nw.SkyOpsArty_Resupply, truck, "подвоз не начался" )

		seconds( 3 * missing + 5 )
		T.eq( S.Total( spg ), S.Capacity() )
		T.eq( S.Count( spg, "krasnopol" ), S.Ordered( spg, "krasnopol" ) )
		T.eq( truck.nw.SkyOpsArty_Stock, stock - missing )
		T.ok( not IsValid( spg.nw.SkyOpsArty_Resupply ), "подвоз не закончился" )
		T.ok( ply.chat[ #ply.chat ]:find( "пополнен" ), ply.chat[ #ply.chat ] )
		teardown()
	end )

	T.it( "грузовик далеко или едет: не подаёт", function()
		local A, spg = setup()
		local S = A.Supply

		S.SetCount( spg, "he", 10 )

		local far = addTruck( A, spg, 40 )

		seconds( 10 )
		T.eq( S.Count( spg, "he" ), 10, "подал с 40 м" )

		far.pos = spg:GetPos() + Vector( 8 * UPM, 0, 0 )
		far.vel = Vector( 5 * UPM, 0, 0 )
		seconds( 10 )
		T.eq( S.Count( spg, "he" ), 10, "подал на ходу" )

		far.vel = Vector( 0, 0, 0 )
		seconds( 10 )
		T.ok( S.Count( spg, "he" ) > 10, "не подал, когда встал рядом" )

		far.pos = spg:GetPos() + Vector( 60 * UPM, 0, 0 )
		seconds( 1 )
		T.ok( not IsValid( spg.nw.SkyOpsArty_Resupply ), "подвоз не прервался, когда уехал" )
		teardown()
	end )

	T.it( "пустой кузов: подвоз прерывается", function()
		local A, spg = setup()
		local S = A.Supply

		S.SetCount( spg, "he", 0 )

		local truck = addTruck( A, spg, 10 )

		truck.nw.SkyOpsArty_Stock = 2
		seconds( 15 )
		T.eq( truck.nw.SkyOpsArty_Stock, 0 )
		T.eq( S.Count( spg, "he" ), 2 )
		T.ok( not IsValid( spg.nw.SkyOpsArty_Resupply ) )
		teardown()
	end )

	T.it( "заявка: команда меняет состав, сумма не больше вместимости", function()
		local A, spg, ply = setup()
		local S = A.Supply

		gm.commands.skyops_arty_ammo_order( ply, "skyops_arty_ammo_order", { "he=10", "krasnopol=50" } )
		T.eq( S.Ordered( spg, "he" ), 10 )
		T.eq( S.Ordered( spg, "krasnopol" ), 30 )

		local sum = 0

		for _, id in ipairs( S.Shells() ) do sum = sum + S.Ordered( spg, id ) end

		T.ok( sum <= S.Capacity(), "заявка больше вместимости: " .. sum )

		gm.commands.skyops_arty_ammo_order( ply, "skyops_arty_ammo_order", { "bogus=3" } )
		T.ok( ply.chat[ #ply.chat ]:find( "skyops_arty_ammo_order" ), "нет подсказки" )
		teardown()
	end )
	T.it( "КамАЗ: кнопка выгружает катапульту с дроном, вторая убирает обратно", function()
		local A, spg, ply = setup()
		local truck = addTruck( A, spg, 30 )

		kitWorld( A )
		ply.veh = nil
		function ply:InVehicle() return false end
		ply.pos = truck:GetPos() + Vector( 5 * UPM, 0, 0 )

		T.eq( truck.nw.SkyOpsArty_KitDrones, 2 )
		gm.commands.skyops_arty_kit( ply, "skyops_arty_kit", {} )
		gm.think( 30 )

		local cat, drone = kitOf( "sw_uav_catapult" ), kitOf( "sw_orlan10" )

		T.ok( cat and drone, "катапульта или дрон не созданы" )
		T.eq( cat.mounted, drone, "дрон не на катапульте" )
		T.eq( truck.nw.SkyOpsArty_KitDrones, 1 )
		T.ok( truck.nw.SkyOpsArty_KitOut )
		T.ok( drone.station.pos:Distance( truck.pos ) < 20 * UPM, "пульт не у машины" )

		-- дрон улетел: не убирается
		drone.pos = truck.pos + Vector( 500 * UPM, 0, 0 )
		seconds( 3 )
		gm.commands.skyops_arty_kit( ply, "skyops_arty_kit", {} )
		T.ok( drone:IsValid(), "убрали дрон в полёте" )
		T.ok( ply.chat[ #ply.chat ]:find( "Дрон не у машины" ), ply.chat[ #ply.chat ] )

		-- вернулся и стоит
		drone.pos = truck.pos + Vector( 0, 15 * UPM, 0 )
		seconds( 3 )
		gm.commands.skyops_arty_kit( ply, "skyops_arty_kit", {} )
		T.ok( not drone:IsValid() and not cat:IsValid() and not drone.station:IsValid(), "не убрано" )
		T.eq( truck.nw.SkyOpsArty_KitDrones, 2 )
		T.eq( truck.nw.SkyOpsArty_KitOut, false )
		teardown()
	end )

	T.it( "КамАЗ: сбитый дрон потерян, катапульта возвращается", function()
		local A, spg, ply = setup()
		local truck = addTruck( A, spg, 30 )

		kitWorld( A )
		ply.veh = truck

		gm.commands.skyops_arty_kit( ply, "skyops_arty_kit", {} )
		gm.think( 30 )
		kitOf( "sw_orlan10" ):Remove()
		seconds( 3 )
		gm.commands.skyops_arty_kit( ply, "skyops_arty_kit", {} )
		T.eq( truck.nw.SkyOpsArty_KitDrones, 1 )
		T.ok( not kitOf( "sw_uav_catapult" ), "катапульта осталась" )
		T.ok( ply.chat[ #ply.chat ]:find( "потерян" ), ply.chat[ #ply.chat ] )
		teardown()
	end )
end )
