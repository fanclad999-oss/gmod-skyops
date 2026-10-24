-- luacheck для аддона GMod. Запуск: tests/lint.sh (сначала переписывает синтаксис GLua,
-- потом зовёт luacheck с этим файлом). Новая функция GMod, которой нет в списке ниже,
-- добавляется в read_globals; опечатка в имени так и останется ошибкой.

std = "luajit+gmod"
max_line_length = false
codes = true

ignore = {
	"212", -- неиспользуемый аргумент: колбэки GMod получают аргументы, которые нужны не всем
	"541", -- пустой do..end: так препроцессор записывает continue из GLua
}

-- Глобалы, которые пишет сам аддон
globals = { "SkyOps", "PANEL", "ENT", "SWEP", "TOOL", "GM", "GAMEMODE", "EFFECT" }

stds.gmod = {
	read_globals = {
		-- расширения стандартной библиотеки
		math = { other_fields = true },
		string = { other_fields = true },
		table = { other_fields = true },
		bit = { other_fields = true },
		debug = { other_fields = true },

		-- библиотеки GMod
		"hook", "net", "util", "file", "timer", "ents", "player", "game", "engine", "concommand",
		"cvars", "scripted_ents", "weapons", "surface", "draw", "render", "cam", "vgui", "gui",
		"input", "notification", "language", "derma", "chat", "system", "halo", "killicon",
		"spawnmenu", "list", "physenv", "navmesh", "constraint", "construct", "duplicator", "undo",
		"cleanup", "effects", "sound", "resource", "team", "gamemode", "motionsensor", "steamworks",
		"http", "sql", "coroutine", "jit", "os", "io", "utf8", "baseclass", "drive", "properties",
		"usermessage", "umsg", "matproxy", "markup", "presets", "search", "frame_blend", "achievements",
		"ai", "ai_schedule", "ai_task", "gmod", "gmsave", "saverestore", "serverlist", "widgets",

		-- функции
		"AddCSLuaFile", "include", "CompileFile", "CompileString", "RunString", "RunConsoleCommand",
		"CreateConVar", "CreateClientConVar", "GetConVar", "GetConVarNumber", "GetConVarString",
		"IsValid", "IsEntity", "isentity", "isnumber", "isstring", "istable", "isfunction", "isbool",
		"isvector", "isangle", "ismatrix", "ispanel", "TypeID", "tobool", "Format",
		"Vector", "Angle", "Color", "Matrix", "Material", "CreateMaterial", "Mesh", "EffectData",
		"DamageInfo", "Entity", "Player", "LocalPlayer", "CurTime", "RealTime", "SysTime",
		"UnPredictedCurTime", "FrameTime", "FrameNumber", "ScrW", "ScrH", "ScreenScale", "Lerp",
		"LerpVector", "LerpAngle", "Sound", "SoundDuration", "EmitSound", "Msg", "MsgN", "MsgC",
		"ErrorNoHalt", "ErrorNoHaltWithStack", "PrintTable", "PrintMessage", "ProtectedCall",
		"ClientsideModel", "ParticleEmitter", "DermaMenu", "Derma_Query", "Derma_StringRequest",
		"Derma_Message", "DrawColorModify", "EyePos", "EyeAngles", "EyeVector", "GetRenderTarget",
		"GetRenderTargetEx", "HSVToColor", "ColorToHSV", "ColorAlpha", "SortedPairs",
		"SortedPairsByValue", "RandomPairs", "AccessorFunc", "DEFINE_BASECLASS", "Model",
		"Localize", "GetHostName", "SetClipboardText", "OnModelLoaded", "HTTP", "BroadcastLua",
		"SendUserMessage", "VectorRand", "AngleRand", "WorldToLocal", "LocalToWorld",
		"FindMetaTable", "RegisterMetaTable", "DynamicLight", "AddConsoleCommand", "GetGlobalBool",
		"GetGlobalInt", "GetGlobalFloat", "GetGlobalString", "GetGlobalEntity", "SetGlobalBool",
		"SetGlobalInt", "SetGlobalFloat", "SetGlobalString", "SetGlobalEntity", "GetGlobal2Bool",
		"SetGlobal2Bool", "VGUIFrameTime", "gui_MousePos",

		-- значения и константы
		"SERVER", "CLIENT", "NULL", "vector_origin", "vector_up", "angle_zero", "color_white",
		"color_black", "color_transparent", "VERSION", "BRANCH", "MENU_DLL",
		"FILL", "TOP", "BOTTOM", "LEFT", "RIGHT", "NODOCK",

		-- сторонние аддоны, которые код проверяет на наличие
		"KIR", "InfMap", "LVS", "SW_Bombs", "Glide", "simfphys",
	},
}

-- константы GMod с префиксами (KEY_*, MOUSE_*, FCVAR_* и т. п.) проще разрешить шаблоном
local prefixes = {
	"KEY_", "MOUSE_", "BUTTON_CODE_", "JOYSTICK_", "FCVAR_", "MASK_", "CONTENTS_", "COLLISION_GROUP_",
	"SOLID_", "MOVETYPE_", "TEXT_ALIGN_", "NOTIFY_", "HUD_PRINT", "IN_", "DMG_", "SURF_", "RENDERMODE_",
	"RENDERGROUP_", "MATERIAL_", "STENCIL_", "BLEND_", "TEXFILTER_", "TYPE_", "SIM_", "EF_", "FL_",
	"FSOLID_", "TRANSMIT_", "USE_", "ACT_", "SCHED_", "NPC_", "D_", "CAP_", "PLAYERANIMEVENT_",
	"OBS_MODE_", "SND_", "CHAN_", "SNDLVL_", "GESTURE_SLOT_", "BOX_", "ANALOG_", "TEAM_", "EFL_",
}

-- luacheck не умеет шаблонов в именах: перечисляем имена, которые реально встречаются в коде
local names = {}

for _, path in ipairs( ( function()
	local list = {}
	local p = io.popen( 'find "' .. ( os.getenv( "SKYOPS_LINT_SRC" ) or "lua" ) .. '" -name "*.lua" 2>/dev/null' )

	if p then
		for line in p:lines() do list[ #list + 1 ] = line end
		p:close()
	end

	return list
end )() ) do
	local f = io.open( path, "rb" )

	if f then
		local src = f:read( "*a" )

		f:close()

		for word in src:gmatch( "[%a_][%w_]*" ) do
			for _, pre in ipairs( prefixes ) do
				if word:sub( 1, #pre ) == pre and word:upper() == word then names[ word ] = true end
			end
		end
	end
end

for name in pairs( names ) do table.insert( stds.gmod.read_globals, name ) end
