-- Артиллерия, дрон: запас хода. Стоковый бак дронов (sw_aircraft_fueltank, 100–150)
-- пустеет за несколько минут, а корректировщику нужно висеть над целью долго.
-- Не трогаем расход LVS, а возвращаем в бак часть того, что он потратил за тик:
-- при множителе N топливо уходит в N раз медленнее.

local D = SkyOps.Arty.Drone

local cvMult = CreateConVar( "skyops_arty_drone_fuel", "5", FCVAR_ARCHIVE, "Во сколько раз дольше летают дроны на одном баке (1 = как в аддоне)" )

hook.Add( "Tick", "SkyOpsArty.Drone.Fuel", function()
	local mult = math.max( cvMult:GetFloat(), 1 )

	for _, drone in ipairs( D.All() ) do
		local tank = drone.GetFuelTank and drone:GetFuelTank()

		if IsValid( tank ) and tank.GetFuel and tank.SetFuel then
			local fuel = tank:GetFuel()
			local last = tank.SkyOpsArty_LastFuel

			-- тратим только 1/mult от стокового расхода; дозаправку (рост) не трогаем
			if last and fuel < last and mult > 1 then
				fuel = last - ( last - fuel ) / mult
				tank:SetFuel( fuel )
			end

			tank.SkyOpsArty_LastFuel = fuel
		end
	end
end )
