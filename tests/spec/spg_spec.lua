-- 2S35 целиком (arty/core/sh_spg.lua + sv_spg.lua): развёртывание, автонаводка по запросу
-- интерфейса, перехват стокового выстрела и падение математического снаряда у цели.
-- Сама САУ (LVS-танк) подменена заглушкой: башня поворачивается к углам наводки с
-- конечной скоростью, дуло смотрит по башне.

local gm, T = ...

local FILES = { "skyops/arty/core/sh_spg.lua", "skyops/arty/core/sv_spg.lua", "skyops/arty/core/sv_ballistics.lua" }

local UPM = 40

-- заглушка sw_2s35. opts.barrel: длина ствола от оси цапф до дула, м; opts.yaw: курс корпуса
local function makeSPG( opts )
	local spg = gm.entity( {
		class = "sw_2s35",
		pos = opts.pos,
		ang = Angle( 0, opts.yaw or 0, 0 ),
		TurretAimRate = 40,
		TurretRateDestroyedMul = 0.25,
		TurretPitchMin = -75, TurretPitchMax = 5,
		TurretPitchPoseParameterName = "turret_pitch", TurretYawPoseParameterName = "turret_yaw",
		TurretPitchOffset = 0, TurretYawOffset = 0, TurretPitchMul = 1, TurretYawMul = 1,
		turretP = 0, turretY = 0, shellType = 0, hp = 1000, shots = 0,
	} )

	function spg:GetHP() return self.hp end
	function spg:GetTurretEnabled() return true end
	function spg:GetTurretDamaged() return false end
	function spg:GetTurretPitch() return self.turretP end
	function spg:GetTurretYaw() return self.turretY end
	function spg:SetTurretPitch( v ) self.turretP = v end
	function spg:SetTurretYaw( v ) self.turretY = v end
	function spg:SetPoseParameter() end
	function spg:StopTurretSound() end
	function spg:StopTurretSoundDMG() end
	function spg:CalcTurretSound() end
	function spg:GetEngineActive() return false end
	function spg:StopEngine() end
	function spg:GetShellType() return self.shellType end
	function spg:SetShellType( t ) self.shellType = t end
	function spg:GetDriver() return opts.ply end
	function spg:GetPassenger( pod ) return pod == 2 and opts.ply or nil end

	-- стоковое наведение LVS (мышь): в тестах башня стоит
	function spg:AimTurret() end

	spg.phys = { IsValid = function() return true end, EnableMotion = function( _, m ) spg.frozen = not m end, Wake = function() end }

	function spg:LookupAttachment( name ) return name == "muzzle" and 1 or 0 end

	function spg:GetAttachment( id )
		if id ~= 1 then return nil end

		local ang = Angle( self.turretP, self.ang.y + self.turretY, 0 )
		local pivot = self.pos + Vector( 0, 0, 2.5 * UPM )

		return { Pos = pivot + ang:Forward() * ( opts.barrel or 0 ) * UPM, Ang = ang }
	end

	-- оружие наводчика: [1] тепловизор, [2] пушка
	local handler = { ammo = 30, nextAttack = 0, heat = 0, selected = 1 }

	function handler:IsValid() return true end
	function handler:GetSelectedWeapon() return self.selected end
	function handler:SelectWeapon( id ) self.selected = id end
	function handler:GetMaxAmmo() return 30 end
	function handler:GetAmmo() return self.ammo end
	function handler:GetOverheated() return false end
	function handler:CanAttack() return gm.time >= self.nextAttack end
	function handler:SetNextAttack( t ) self.nextAttack = t end
	function handler:GetHeat() return self.heat end
	function handler:SetHeat( h ) self.heat = h end

	spg.WEAPONS = {
		[ 2 ] = {
			{ Icon = "flir" },
			{
				Icon = true, Delay = 6,
				Attack = function( h )
					h.ammo = h.ammo - 1
					spg.shots = spg.shots + 1

					local stock = _G.ents.Create( "sw_bomb_fab100_v3" )

					stock:SetPos( spg:GetAttachment( 1 ).Pos )
					spg._ProjectileEntity = stock
				end,
			},
		},
	}

	function spg:GetWeaponHandler( pod ) return pod == 2 and handler or nil end

	spg.handler = handler

	return spg
end

local function setup( opts )
	opts = opts or {}
	gm.reset( "server" )

	_G.KIR = {
		S = UPM,
		MeshHeight = function() return ( opts.ground or 100 ) * UPM end,
	}

	gm.created = {}
	gm.entityFactory = function( class )
		local e = gm.entity( { class = class } )

		if class == "sw_bomb_fab100_v3" then
			function e:Explode( pos ) gm.explosions = gm.explosions or {} table.insert( gm.explosions, pos ) end
		end

		table.insert( gm.entities, e )
		table.insert( gm.created, e )
		_G.hook.Run( "OnEntityCreated", e )

		return e
	end

	gm.loadDirs( { "skyops/core/", "skyops/arty/core/" } )

	_G.GetConVar( "skyops_arty_dispersion" ):SetFloat( 0 )
	_G.GetConVar( "skyops_arty_mode" ):SetString( "auto" )
	_G.GetConVar( "skyops_arty_timescale" ):SetFloat( 10 )

	local ply = gm.entity( { class = "player", player = true } )

	gm.players = { ply }

	local A = _G.SkyOps.Arty
	local spg = makeSPG( {
		pos = A.Grid.FromGrid( 50000, 50000, opts.ground or 100 ),
		yaw = opts.yaw, barrel = opts.barrel, ply = ply,
	} )

	function ply:lvsGetVehicle() return spg end

	table.insert( gm.entities, spg )
	_G.hook.Run( "OnEntityCreated", spg )
	gm.think( 1 )

	return A, spg, ply
end

local function teardown() _G.KIR = nil gm.entityFactory = nil end

-- кадр: LVS крутит башню (AimTurret) и Think
local function frames( spg, n, until_ )
	for _ = 1, n do
		spg:AimTurret()
		gm.think( 1, 1 / 66 )

		if until_ and until_() then return true end
	end

	return false
end

local function impacts()
	local list = {}

	for _, m in ipairs( gm.netSent ) do
		if m.name == "skyops_arty_impact" then list[ #list + 1 ] = m.data[ 1 ][ 2 ] end
	end

	return list
end

local ok, why = T.requires( gm, unpack( FILES ) )

T.describe( "2S35: автонаводка и выстрел", function()
	if not ok then return T.it( "файлы на месте", function() T.skip( why ) end ) end

	local function autoShot( opts, tx, ty )
		local A, spg, ply = setup( opts )
		local target = A.Grid.FromGrid( tx, ty, opts.ground or 100 )

		gm.deliver( "skyops_arty_auto", { spg, target, "he", 0 }, ply )
		T.ok( spg.nw.SkyOpsArty_Auto, "автонаводка не запустилась: " .. tostring( ply.chat and ply.chat[ #ply.chat ] ) )

		local fired = frames( spg, 66 * 90, function() return spg.shots > 0 end )

		T.ok( fired, "САУ не выстрелила за 90 с; чат: " .. table.concat( ply.chat or {}, " | " ) )
		T.eq( spg.nw.SkyOpsArty_State, A.SPG.STATE_DEPLOYED, "САУ не развёрнута" )

		local done = frames( spg, 66 * 60, function() return #impacts() > 0 end )

		T.ok( done, "снаряд не упал" )

		local x, y = A.Grid.ToGrid( impacts()[ 1 ] )

		return math.sqrt( ( x - tx ) ^ 2 + ( y - ty ) ^ 2 ), A, spg, ply
	end

	T.it( "сток-снаряд перехвачен и удалён, вместо него летит математический", function()
		local _, _, spg = autoShot( {}, 50000, 62000 )
		local stock

		for _, e in ipairs( gm.created ) do
			if e.class == "sw_bomb_fab100_v3" and not e.SkyOpsArty_Ours then stock = e end
		end

		T.ok( stock, "сток-снаряд не создавался" )
		T.ok( not stock:IsValid(), "сток-снаряд не удалён" )
		T.eq( spg.shots, 1, "лишние выстрелы" )
		teardown()
	end )

	T.it( "дуло на оси башни: разрыв у цели (до 5 м) при любом курсе корпуса", function()
		for _, case in ipairs( {
			{ yaw = 0, tx = 50000, ty = 62000 },
			{ yaw = 90, tx = 58000, ty = 41000 },
			{ yaw = -135, tx = 31000, ty = 35000 },
			{ yaw = 33, tx = 50300, ty = 54000 },
		} ) do
			local miss = autoShot( { yaw = case.yaw }, case.tx, case.ty )

			T.ok( miss < 5, string.format( "курс %d, цель %d %d: промах %.1f м", case.yaw, case.tx, case.ty, miss ) )
			teardown()
		end
	end )

	T.it( "ствол 7 м: промах от выноса дула меньше 25 м", function()
		local miss = autoShot( { barrel = 7 }, 50000, 70000 )

		T.ok( miss < 25, string.format( "промах %.1f м", miss ) )
		teardown()
	end )

	T.it( "после выстрела в чат уходят установки, автонаводка снята", function()
		local _, _, spg, ply = autoShot( {}, 50000, 60000 )

		T.eq( spg.nw.SkyOpsArty_Auto, false )
		T.ok( ply.chat and ply.chat[ #ply.chat ]:find( "Выстрел" ), "нет сообщения о выстреле" )
		teardown()
	end )

	T.it( "режим «хардкор» отклоняет автонаводку", function()
		local A, spg, ply = setup()

		_G.GetConVar( "skyops_arty_mode" ):SetString( "hardcore" )
		gm.deliver( "skyops_arty_auto", { spg, A.Grid.FromGrid( 50000, 60000 ), "he", 0 }, ply )
		T.ok( not spg.nw.SkyOpsArty_Auto, "автонаводка в хардкоре" )
		T.ok( ply.chat and ply.chat[ #ply.chat ]:find( "хардкор" ), "нет объяснения в чате" )
		teardown()
	end )

	T.it( "ручная наводка: стрелка влево = угломер +1, вверх = прицел +1", function()
		local A, spg, ply = setup()

		gm.commands.skyops_arty_deploy( ply, "skyops_arty_deploy", {} )
		frames( spg, 66 * 11 )
		T.eq( spg.nw.SkyOpsArty_State, A.SPG.STATE_DEPLOYED )

		local FC = A.FireComp

		-- поднять ствол, чтобы не упираться в предел
		spg.nw.SkyOpsArty_LayP = -10
		frames( spg, 66 * 2 )

		local d0, e0 = FC.GunLaying( spg )

		gm.deliver( "skyops_arty_lay", { A.SPG.LAY_LEFT }, ply )
		gm.deliver( "skyops_arty_lay", { 0 }, ply )
		gm.deliver( "skyops_arty_lay", { A.SPG.LAY_UP }, ply )
		gm.deliver( "skyops_arty_lay", { 0 }, ply )
		frames( spg, 66 )

		local d1, e1 = FC.GunLaying( spg )

		T.near( FC.MilsDiff( d1, d0 ), 1, 1e-3, "угломер" )
		T.near( e1 - e0, 1, 1e-3, "прицел" )
		teardown()
	end )

	T.it( "основное направление после развёртывания кратно 1-00 и по корпусу", function()
		local A, spg, ply = setup( { yaw = 37 } )

		gm.commands.skyops_arty_deploy( ply, "skyops_arty_deploy", {} )
		frames( spg, 66 * 11 )

		local base = spg.nw.SkyOpsArty_BaseDir
		local hull = A.Grid.YawToMils( 37 )

		T.eq( base % 100, 0, "не кратно 1-00" )
		T.ok( math.abs( A.FireComp.MilsDiff( base, hull ) ) <= 50, "далеко от курса корпуса" )
		T.ok( spg.frozen, "корпус не заморожен на позиции" )
		teardown()
	end )

	T.it( "skyops_arty_charge next перебирает заряды по кругу", function()
		local A, spg, ply = setup()
		local seen = {}

		for _ = 1, 7 do
			gm.commands.skyops_arty_charge( ply, "skyops_arty_charge", { "next" } )
			seen[ #seen + 1 ] = spg.nw.SkyOpsArty_Charge
		end

		T.eq( table.concat( seen, "," ), "2,3,4,5,6,1,2" )
		T.ok( A.FireComp.GetCharge( "he", spg.nw.SkyOpsArty_Charge ), "заряд не существует" )
		teardown()
	end )
end )
