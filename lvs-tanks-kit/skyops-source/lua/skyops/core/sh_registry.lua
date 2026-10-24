-- Role -> entity class registry. Missions refer to roles ("su34", "s75"),
-- never to raw classes, so third-party class renames are fixed here only.

SkyOps.Registry = SkyOps.Registry or {}

local R = SkyOps.Registry

-- crew: seat index (0 = driver, 1.. = AddPassengerSeat order) -> role
R.Aircraft = {
	su34 = {
		class = "sw_su34", name = "Су-34", workshop = 3319073025,
		crew = { [0] = "pilot", [1] = "wso" },
	},
	tornado_ids = {
		class = "sw_tornado", name = "Tornado IDS", workshop = 3489256708,
		crew = { [0] = "pilot", [1] = "wso" },
	},
	f14a = {
		class = "sw_f14a", name = "F-14A", workshop = 3408992578,
		crew = { [0] = "pilot", [1] = "rio" },
	},
	su25sm3 = {
		class = "sw_su25sm3", name = "Су-25СМ3", workshop = 3261220817,
		crew = { [0] = "pilot" },
	},
}

-- parts: classes that make up one site; spawn = the class that creates the rest
-- radar: search range (m), radar mast height (m), max engagement range (m)
R.AirDefense = {
	s75 = {
		name = "С-75", workshop = 3470355913, spawn = "sw_snr75",
		parts = { snr75 = "sw_snr75", launcher = "sw_s75", p12_radar = "sw_p12" },
		radar = { search = 120000, mast = 10, engage = 43000 },
	},
	tor_m1 = {
		name = "Тор-М1", workshop = 3291755974, spawn = "sw_torm1",
		radar = { search = 25000, mast = 6, engage = 12000 },
	},
	osa = {
		name = "Оса (9К33М3)", workshop = 3319287696, spawn = "sw_9k33m3",
		radar = { search = 30000, mast = 5, engage = 10000 },
	},
	roland = {
		name = "Roland (FlaRakPz I)", workshop = 3488791956, spawn = "sw_flarakpz1",
		radar = { search = 16000, mast = 5, engage = 8000 },
	},
	aaa = { name = "Зенитная артиллерия", spawn = "lvs_trailer_flak" },
}

function R.GetAircraft( role ) return R.Aircraft[ role ] end
function R.GetAirDefense( system ) return R.AirDefense[ system ] end

function R.RoleForClass( class )
	for role, data in pairs( R.Aircraft ) do
		if data.class == class then return role, "aircraft" end
	end
	for system, data in pairs( R.AirDefense ) do
		if data.spawn == class then return system, "airdefense" end
	end
end

-- true when the addon providing a role is installed on this machine
function R.IsAvailable( data )
	return data ~= nil and scripted_ents.GetStored( data.spawn or data.class ) ~= nil
end
