-- Заглушки GMod API для обычного LuaJIT: ровно столько, сколько нужно, чтобы загрузить
-- файлы аддона и прогнать чистую математику (сетка, вычислитель, полёт снаряда).
--
-- local gm = dofile( "tests/lib/gmod.lua" )
-- gm.reset( "server" )            -- новый _G-мир: SERVER = true, пустые хуки, конвары, net
-- gm.include( "skyops/arty/core/sh_grid.lua" )  -- путь от lua/, как include() в GMod
--
-- Корень с папкой lua/ задаёт переменная окружения SKYOPS_ROOT (по умолчанию текущая папка).

local gm = {}

-- стандартные функции Lua, которые заглушки переустанавливают при каждом reset
local BASE = { print = print, bit = bit or require( "bit" ), unpack = unpack or table.unpack }

gm.root = ( os.getenv( "SKYOPS_ROOT" ) or "." ):gsub( "/$", "" )

-- Мелочи ------------------------------------------------------------------------------

local function isnumber( v ) return type( v ) == "number" end
local function isstring( v ) return type( v ) == "string" end
local function istable( v ) return type( v ) == "table" end
local function isfunction( v ) return type( v ) == "function" end
local function isbool( v ) return type( v ) == "boolean" end

-- Vector -------------------------------------------------------------------------------

local VEC = {}
VEC.__index = VEC

local function Vector( x, y, z )
	if type( x ) == "table" then x, y, z = x.x, x.y, x.z end

	return setmetatable( { x = x or 0, y = y or 0, z = z or 0, __vector = true }, VEC )
end

local function isvector( v ) return type( v ) == "table" and getmetatable( v ) == VEC end

VEC.__add = function( a, b ) return Vector( a.x + b.x, a.y + b.y, a.z + b.z ) end
VEC.__sub = function( a, b ) return Vector( a.x - b.x, a.y - b.y, a.z - b.z ) end
VEC.__unm = function( a ) return Vector( -a.x, -a.y, -a.z ) end
VEC.__eq = function( a, b ) return a.x == b.x and a.y == b.y and a.z == b.z end
VEC.__tostring = function( a ) return string.format( "%.4f %.4f %.4f", a.x, a.y, a.z ) end

VEC.__mul = function( a, b )
	if type( a ) == "number" then a, b = b, a end
	if type( b ) == "number" then return Vector( a.x * b, a.y * b, a.z * b ) end

	return Vector( a.x * b.x, a.y * b.y, a.z * b.z )
end

VEC.__div = function( a, b )
	if type( b ) == "number" then return Vector( a.x / b, a.y / b, a.z / b ) end

	return Vector( a.x / b.x, a.y / b.y, a.z / b.z )
end

function VEC:Length() return math.sqrt( self.x ^ 2 + self.y ^ 2 + self.z ^ 2 ) end
function VEC:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function VEC:Length2D() return math.sqrt( self.x ^ 2 + self.y ^ 2 ) end
function VEC:Length2DSqr() return self.x ^ 2 + self.y ^ 2 end
function VEC:Distance( b ) return ( self - b ):Length() end
function VEC:DistToSqr( b ) return ( self - b ):LengthSqr() end
function VEC:Distance2D( b ) return ( self - b ):Length2D() end
function VEC:Dot( b ) return self.x * b.x + self.y * b.y + self.z * b.z end
function VEC:Cross( b ) return Vector( self.y * b.z - self.z * b.y, self.z * b.x - self.x * b.z, self.x * b.y - self.y * b.x ) end
function VEC:IsZero() return self.x == 0 and self.y == 0 and self.z == 0 end
function VEC:Unpack() return self.x, self.y, self.z end

function VEC:GetNormalized()
	local l = self:Length()

	if l == 0 then return Vector( 0, 0, 0 ) end

	return self / l
end

function VEC:Normalize()
	local n = self:GetNormalized()

	self.x, self.y, self.z = n.x, n.y, n.z
end

function VEC:Add( b ) self.x, self.y, self.z = self.x + b.x, self.y + b.y, self.z + b.z end
function VEC:Sub( b ) self.x, self.y, self.z = self.x - b.x, self.y - b.y, self.z - b.z end
function VEC:Mul( k ) self.x, self.y, self.z = self.x * k, self.y * k, self.z * k end

-- Angle --------------------------------------------------------------------------------

local ANG = {}
ANG.__index = ANG

local function Angle( p, y, r )
	if type( p ) == "table" then p, y, r = p.p, p.y, p.r end

	return setmetatable( { p = p or 0, y = y or 0, r = r or 0 }, ANG )
end

local function isangle( v ) return type( v ) == "table" and getmetatable( v ) == ANG end

ANG.__add = function( a, b ) return Angle( a.p + b.p, a.y + b.y, a.r + b.r ) end
ANG.__sub = function( a, b ) return Angle( a.p - b.p, a.y - b.y, a.r - b.r ) end
ANG.__eq = function( a, b ) return a.p == b.p and a.y == b.y and a.r == b.r end
ANG.__tostring = function( a ) return string.format( "%.4f %.4f %.4f", a.p, a.y, a.r ) end

-- Source: pitch положителен вниз, yaw против часовой от +X
function ANG:Forward()
	local p, y = math.rad( self.p ), math.rad( self.y )

	return Vector( math.cos( p ) * math.cos( y ), math.cos( p ) * math.sin( y ), -math.sin( p ) )
end

function ANG:Right()
	local y = math.rad( self.y )

	-- без крена: правая сторона горизонтальна
	return Vector( math.sin( y ), -math.cos( y ), 0 )
end

function ANG:Up() return self:Right():Cross( self:Forward() ) end
function ANG:Unpack() return self.p, self.y, self.r end

function VEC:Angle()
	local yaw = math.deg( math.atan2( self.y, self.x ) ) % 360
	local pitch = math.deg( math.atan2( -self.z, math.sqrt( self.x ^ 2 + self.y ^ 2 ) ) )

	if pitch < 0 then pitch = pitch + 360 end

	return Angle( pitch, yaw, 0 )
end

-- Color --------------------------------------------------------------------------------

local function Color( r, g, b, a ) return { r = r or 255, g = g or 255, b = b or 255, a = a or 255 } end

-- math / string / table расширения GMod ----------------------------------------------

local function installLibs()
	function math.Clamp( v, lo, hi ) return math.min( math.max( v, lo ), hi ) end

	function math.Round( v, dec )
		local m = 10 ^ ( dec or 0 )

		return math.floor( v * m + 0.5 ) / m
	end

	function math.NormalizeAngle( a ) return ( a + 180 ) % 360 - 180 end

	function math.AngleDifference( a, b )
		local d = math.NormalizeAngle( a - b )

		if d < 180 then return d end

		return d - 360
	end

	function math.Approach( cur, target, inc )
		inc = math.abs( inc )

		if cur < target then return math.min( cur + inc, target ) end
		if cur > target then return math.max( cur - inc, target ) end

		return target
	end

	function math.ApproachAngle( cur, target, inc )
		local diff = math.AngleDifference( target, cur )

		return math.Approach( cur, cur + diff, inc )
	end

	function math.Remap( v, a, b, c, d ) return c + ( d - c ) * ( v - a ) / ( b - a ) end
	function math.Rand( a, b ) return a + ( b - a ) * math.random() end
	function math.Distance( x1, y1, x2, y2 ) return math.sqrt( ( x2 - x1 ) ^ 2 + ( y2 - y1 ) ^ 2 ) end
	function math.Truncate( v, dec ) local m = 10 ^ ( dec or 0 ) return ( v >= 0 and math.floor or math.ceil )( v * m ) / m end
	function math.IsNearlyEqual( a, b, tol ) return math.abs( a - b ) <= ( tol or 1e-7 ) end

	function string.EndsWith( s, e ) return e == "" or s:sub( -#e ) == e end
	function string.StartsWith( s, b ) return s:sub( 1, #b ) == b end
	string.StartWith = string.StartsWith
	function string.GetFileFromFilename( p ) return p:match( "([^/\\]+)$" ) or "" end
	function string.GetPathFromFilename( p ) return p:match( "^(.*[/\\])" ) or "" end
	function string.Trim( s ) return ( s:gsub( "^%s+", "" ):gsub( "%s+$", "" ) ) end
	function string.Replace( s, a, b ) return ( s:gsub( a:gsub( "%p", "%%%0" ), ( b:gsub( "%%", "%%%%" ) ) ) ) end

	function string.Explode( sep, s )
		local out, pos = {}, 1

		while true do
			local a, b = s:find( sep, pos, true )

			if not a then out[ #out + 1 ] = s:sub( pos ) break end

			out[ #out + 1 ] = s:sub( pos, a - 1 )
			pos = b + 1
		end

		return out
	end

	function string.Split( s, sep ) return string.Explode( sep, s ) end
	function string.Comma( n ) return tostring( n ) end

	function table.Count( t ) local n = 0 for _ in pairs( t ) do n = n + 1 end return n end
	function table.IsEmpty( t ) return next( t ) == nil end
	function table.HasValue( t, v ) for _, x in pairs( t ) do if x == v then return true end end return false end
	function table.GetKeys( t ) local k = {} for key in pairs( t ) do k[ #k + 1 ] = key end return k end
	function table.Merge( a, b ) for k, v in pairs( b ) do a[ k ] = v end return a end

	function table.Copy( t )
		local c = {}

		for k, v in pairs( t ) do c[ k ] = type( v ) == "table" and table.Copy( v ) or v end

		return setmetatable( c, getmetatable( t ) )
	end
end

-- «Чёрная дыра»: любой индекс и вызов возвращают её же. Для клиентских библиотек
-- отрисовки, которые при загрузке файлов только регистрируются.
local Void = setmetatable( {}, {} )

getmetatable( Void ).__index = function() return Void end
getmetatable( Void ).__call = function() return Void end
getmetatable( Void ).__newindex = function() end
getmetatable( Void ).__tostring = function() return "Void" end
getmetatable( Void ).__concat = function() return "Void" end

gm.Void = Void

-- Мир ----------------------------------------------------------------------------------

-- имена, которые в GMod есть, но в этих тестах не нужны: читаются как nil без жалоб
gm.KnownMissing = {
	KIR = true, InfMap = true, LVS = true, SW_Bombs = true, Glide = true,
	SkyOps = true, -- «SkyOps = SkyOps or {}» в начале файлов
}

function gm.reset( realm )
	realm = realm or "server"

	installLibs()

	gm.realm = realm
	gm.time = 0
	gm.frame = 1 / 66
	gm.hooks = {}
	gm.convars = {}
	gm.netStrings = {}
	gm.netReceivers = {}
	gm.netSent = {}
	gm.commands = {}
	gm.timers = {}
	gm.included = {}
	gm.entities = {}
	gm.unknownGlobals = {}

	local G = _G

	-- старые глобалы прошлого мира стираем, чтобы тесты не влияли друг на друга
	for _, name in ipairs( gm._installed or {} ) do G[ name ] = nil end

	local env = {}

	env.SERVER = realm == "server"
	env.CLIENT = realm == "client"

	env.Vector, env.Angle, env.Color = Vector, Angle, Color
	env.vector_origin = Vector( 0, 0, 0 )
	env.vector_up = Vector( 0, 0, 1 )
	env.angle_zero = Angle( 0, 0, 0 )
	env.color_white = Color( 255, 255, 255 )
	env.color_black = Color( 0, 0, 0 )
	env.color_transparent = Color( 255, 255, 255, 0 )

	env.isnumber, env.isstring, env.istable, env.isfunction, env.isbool = isnumber, isstring, istable, isfunction, isbool
	env.isvector, env.isangle = isvector, isangle
	env.isentity = function( v ) return type( v ) == "table" and v.__entity == true end
	env.IsEntity = env.isentity

	env.IsValid = function( v )
		if v == nil or v == false then return false end
		if type( v ) == "table" and v.IsValid then return v:IsValid() and true or false end

		return v ~= nil
	end

	env.NULL = setmetatable( { __entity = true }, { __index = function() return function() end end } )
	rawset( env.NULL, "IsValid", function() return false end )

	env.CurTime = function() return gm.time end
	env.RealTime = env.CurTime
	env.SysTime = env.CurTime
	env.UnPredictedCurTime = env.CurTime
	env.FrameTime = function() return gm.frame end
	env.engine = { TickInterval = function() return 1 / 66 end, ActiveGamemode = function() return "sandbox" end }
	env.game = {
		GetMap = function() return "gm_test" end,
		SinglePlayer = function() return true end,
		GetWorld = function() return gm.world end,
	}

	env.print = BASE.print
	env.Msg = function( ... ) io.write( ... ) end
	env.MsgN = function( ... ) io.write( ... ) io.write( "\n" ) end
	env.MsgC = function( ... )
		for _, v in ipairs( { ... } ) do if type( v ) ~= "table" then io.write( tostring( v ) ) end end
	end
	env.ErrorNoHalt = function( ... ) gm.errors = gm.errors or {} table.insert( gm.errors, table.concat( { ... } ) ) end
	env.ErrorNoHaltWithStack = env.ErrorNoHalt
	env.PrintTable = function() end
	env.Format = string.format
	env.tobool = function( v ) return v ~= nil and v ~= false and v ~= 0 and v ~= "0" and v ~= "false" end

	env.bit = BASE.bit
	env.unpack = BASE.unpack

	env.FCVAR_ARCHIVE, env.FCVAR_REPLICATED, env.FCVAR_NOTIFY = 128, 8192, 256
	env.FCVAR_ARCHIVE_XBOX, env.FCVAR_USERINFO, env.FCVAR_CHEAT = 16777216, 512, 16384
	env.FCVAR_NONE, env.FCVAR_PROTECTED, env.FCVAR_SERVER_CAN_EXECUTE = 0, 32, 268435456
	env.MASK_SOLID_BRUSHONLY, env.MASK_SOLID, env.MASK_SHOT, env.MASK_WATER = 16395, 33570827, 1174421507, 16432
	env.NOTIFY_GENERIC, env.NOTIFY_ERROR, env.NOTIFY_UNDO, env.NOTIFY_HINT, env.NOTIFY_CLEANUP = 0, 1, 2, 3, 4
	env.TEXT_ALIGN_LEFT, env.TEXT_ALIGN_CENTER, env.TEXT_ALIGN_RIGHT, env.TEXT_ALIGN_TOP, env.TEXT_ALIGN_BOTTOM = 0, 1, 2, 3, 4
	env.HUD_PRINTTALK, env.HUD_PRINTCENTER, env.HUD_PRINTCONSOLE = 3, 4, 2
	env.MOUSE_LEFT, env.MOUSE_RIGHT, env.MOUSE_MIDDLE, env.MOUSE_WHEEL_UP, env.MOUSE_WHEEL_DOWN = 107, 108, 109, 112, 113
	env.IN_ATTACK, env.IN_ATTACK2, env.IN_USE, env.IN_RELOAD = 1, 2048, 32, 8192
	env.SOLID_NONE, env.SOLID_VPHYSICS, env.MOVETYPE_NONE, env.MOVETYPE_VPHYSICS = 0, 6, 0, 6
	env.COLLISION_GROUP_NONE, env.COLLISION_GROUP_WORLD = 0, 20
	env.RENDERMODE_TRANSCOLOR, env.RENDERMODE_NORMAL = 1, 0
	env.TYPE_NUMBER, env.TYPE_STRING, env.TYPE_TABLE, env.TYPE_VECTOR = 3, 4, 5, 10

	-- коды клавиш (KEY_*): значения настоящие только для тех, что встречаются в коде
	local keys = {
		KEY_NONE = 0, KEY_0 = 1, KEY_1 = 2, KEY_2 = 3, KEY_3 = 4, KEY_4 = 5, KEY_5 = 6, KEY_6 = 7, KEY_7 = 8, KEY_8 = 9, KEY_9 = 10,
		KEY_A = 11, KEY_B = 12, KEY_C = 13, KEY_D = 14, KEY_E = 15, KEY_F = 16, KEY_G = 17, KEY_H = 18, KEY_I = 19, KEY_J = 20,
		KEY_K = 21, KEY_L = 22, KEY_M = 23, KEY_N = 24, KEY_O = 25, KEY_P = 26, KEY_Q = 27, KEY_R = 28, KEY_S = 29, KEY_T = 30,
		KEY_U = 31, KEY_V = 32, KEY_W = 33, KEY_X = 34, KEY_Y = 35, KEY_Z = 36,
		KEY_ENTER = 64, KEY_SPACE = 65, KEY_BACKSPACE = 66, KEY_TAB = 67, KEY_ESCAPE = 70,
		KEY_LSHIFT = 79, KEY_RSHIFT = 80, KEY_LALT = 81, KEY_RALT = 82, KEY_LCONTROL = 83, KEY_RCONTROL = 84,
		KEY_UP = 88, KEY_LEFT = 89, KEY_DOWN = 90, KEY_RIGHT = 91,
		KEY_F1 = 92, KEY_F2 = 93, KEY_F3 = 94, KEY_F4 = 95, KEY_F5 = 96, KEY_F6 = 97, KEY_F7 = 98, KEY_F8 = 99,
		KEY_PAD_PLUS = 50, KEY_PAD_MINUS = 49, KEY_PAD_ENTER = 51,
	}

	for k, v in pairs( keys ) do env[ k ] = v end

	-- hook ----------------------------------------------------------------------------
	env.hook = {
		Add = function( event, id, fn )
			gm.hooks[ event ] = gm.hooks[ event ] or {}
			gm.hooks[ event ][ id ] = fn
		end,
		Remove = function( event, id )
			if gm.hooks[ event ] then gm.hooks[ event ][ id ] = nil end
		end,
		GetTable = function() return gm.hooks end,
	}

	function env.hook.Run( event, ... )
		for _, fn in pairs( gm.hooks[ event ] or {} ) do
			local a, b, c, d = fn( ... )

			if a ~= nil then return a, b, c, d end
		end
	end

	env.hook.Call = function( event, _, ... ) return env.hook.Run( event, ... ) end

	-- convars -------------------------------------------------------------------------
	local CV = {}
	CV.__index = CV

	function CV:GetString() return tostring( self.value ) end
	function CV:GetFloat() return tonumber( self.value ) or 0 end
	function CV:GetInt() return math.floor( tonumber( self.value ) or 0 ) end
	function CV:GetBool() return self:GetInt() ~= 0 end
	function CV:GetName() return self.name end
	function CV:GetDefault() return self.default end
	function CV:GetHelpText() return self.help end
	function CV:SetString( v ) self.value = tostring( v ) end
	function CV:SetFloat( v ) self.value = tostring( v ) end
	function CV:SetInt( v ) self.value = tostring( math.floor( v ) ) end
	function CV:SetBool( v ) self.value = v and "1" or "0" end
	function CV:Revert() self.value = self.default end

	local function MakeCV( name, default, flags, help, lo, hi )
		if gm.convars[ name ] then return gm.convars[ name ] end

		local cv = setmetatable( { name = name, value = tostring( default ), default = tostring( default ), flags = flags, help = help, min = lo, max = hi }, CV )

		gm.convars[ name ] = cv

		return cv
	end

	env.CreateConVar = function( name, default, flags, help, lo, hi )
		if type( flags ) == "table" then
			local f = 0

			for _, v in ipairs( flags ) do f = env.bit.bor( f, v ) end

			flags = f
		end

		return MakeCV( name, default, flags, help, lo, hi )
	end

	env.CreateClientConVar = function( name, default, _, _, help, lo, hi )
		if realm ~= "client" then return nil end

		return MakeCV( name, default, 0, help, lo, hi )
	end

	env.GetConVar = function( name ) return gm.convars[ name ] end
	env.GetConVarNumber = function( name ) local c = gm.convars[ name ] return c and c:GetFloat() or 0 end
	env.GetConVarString = function( name ) local c = gm.convars[ name ] return c and c:GetString() or "" end
	env.cvars = { AddChangeCallback = function() end, RemoveChangeCallback = function() end }

	env.RunConsoleCommand = function( name, ... )
		local args = { ... }

		if gm.convars[ name ] then
			gm.convars[ name ].value = tostring( args[ 1 ] )
		elseif gm.commands[ name ] then
			gm.commands[ name ]( gm.localPlayer, name, args, table.concat( args, " " ) )
		end
	end

	env.concommand = {
		Add = function( name, fn ) gm.commands[ name ] = fn end,
		Remove = function( name ) gm.commands[ name ] = nil end,
	}

	-- net -----------------------------------------------------------------------------
	local outgoing

	env.util = {
		AddNetworkString = function( name )
			if not gm.netStrings[ name ] then gm.netStrings[ name ] = table.Count( gm.netStrings ) + 1 end

			return gm.netStrings[ name ]
		end,
		NetworkStringToID = function( name ) return gm.netStrings[ name ] or 0 end,
		TraceLine = function( t ) return { Hit = false, HitPos = t.endpos, Fraction = 1, StartPos = t.start, HitWorld = false } end,
		TraceHull = function( t ) return { Hit = false, HitPos = t.endpos, Fraction = 1, StartPos = t.start } end,
		QuickTrace = function( a, b ) return { Hit = false, HitPos = a + b, Fraction = 1 } end,
		Effect = function() end,
		BlastDamage = function( ... ) gm.blasts = gm.blasts or {} table.insert( gm.blasts, { ... } ) end,
		ScreenShake = function() end,
		Decal = function() end,
		IsInWorld = function() return true end,
		TableToJSON = function() return "{}" end,
		JSONToTable = function() return {} end,
		CRC = function( s ) return tostring( #s ) end,
	}

	local function W( kind ) return function( v ) table.insert( outgoing.data, { kind, v } ) end end

	env.net = {
		Start = function( name )
			assert( gm.netStrings[ name ] or realm == "client", "net.Start без util.AddNetworkString: " .. tostring( name ) )
			outgoing = { name = name, data = {} }
		end,
		Receive = function( name, fn ) gm.netReceivers[ name ] = fn end,
		WriteVector = W( "vector" ), WriteAngle = W( "angle" ), WriteString = W( "string" ),
		WriteFloat = W( "float" ), WriteDouble = W( "double" ), WriteEntity = W( "entity" ),
		WriteBool = W( "bool" ), WriteTable = W( "table" ), WriteColor = W( "color" ), WriteNormal = W( "normal" ),
		WriteUInt = function( v, bits )
			assert( v >= 0 and v < 2 ^ bits, string.format( "net.WriteUInt: %s не помещается в %d бит", tostring( v ), bits ) )
			table.insert( outgoing.data, { "uint", v } )
		end,
		WriteInt = function( v, bits ) table.insert( outgoing.data, { "int", v, bits } ) end,
		Send = function( to ) outgoing.to = to table.insert( gm.netSent, outgoing ) end,
		Broadcast = function() outgoing.to = "all" table.insert( gm.netSent, outgoing ) end,
		SendToServer = function() outgoing.to = "server" table.insert( gm.netSent, outgoing ) end,
		SendPVS = function() outgoing.to = "pvs" table.insert( gm.netSent, outgoing ) end,
		SendOmit = function() outgoing.to = "omit" table.insert( gm.netSent, outgoing ) end,
	}

	-- доставка сообщения обработчику: values читаются по порядку любыми net.Read*
	function gm.deliver( name, values, ply )
		local i = 0
		local function R() i = i + 1 return values[ i ] end

		for _, fn in ipairs( { "ReadVector", "ReadAngle", "ReadString", "ReadFloat", "ReadDouble", "ReadEntity", "ReadBool", "ReadUInt", "ReadInt", "ReadTable", "ReadColor", "ReadNormal" } ) do
			env.net[ fn ] = R
			G.net[ fn ] = R
		end

		local fn = gm.netReceivers[ name ]

		assert( fn, "нет net.Receive для " .. name )

		return fn( 64, ply )
	end

	-- таймеры ---------------------------------------------------------------------------
	env.timer = {
		Simple = function( delay, fn ) table.insert( gm.timers, { at = gm.time + delay, fn = fn } ) end,
		Create = function( id, delay, reps, fn ) gm.timers[ id ] = { at = gm.time + delay, fn = fn, delay = delay, reps = reps } end,
		Remove = function( id ) gm.timers[ id ] = nil end,
		Exists = function( id ) return gm.timers[ id ] ~= nil end,
		Adjust = function() end,
	}

	-- файлы и include -------------------------------------------------------------------
	local function ls( dir )
		local files, folders = {}, {}
		local p = io.popen( 'ls -1Ap "' .. dir .. '" 2>/dev/null' )

		if not p then return files, folders end

		for line in p:lines() do
			if line:sub( -1 ) == "/" then folders[ #folders + 1 ] = line:sub( 1, -2 ) else files[ #files + 1 ] = line end
		end

		p:close()

		return files, folders
	end

	gm.ls = ls

	env.file = {
		Find = function( pattern, path )
			assert( path == "LUA", "file.Find в тестах умеет только LUA" )

			local dir, mask = pattern:match( "^(.-)([^/]*)$" )
			local files, folders = ls( gm.root .. "/lua/" .. dir )
			local lp = "^" .. mask:gsub( "%.", "%%." ):gsub( "%*", ".*" ) .. "$"
			local f2 = {}

			for _, f in ipairs( files ) do if f:match( lp ) then f2[ #f2 + 1 ] = f end end

			return f2, folders
		end,
		Exists = function( name, path )
			if path ~= "LUA" then return false end

			local f = io.open( gm.root .. "/lua/" .. name )

			if f then f:close() return true end

			return false
		end,
		Read = function() return nil end,
		Write = function() end,
		Append = function() end,
		CreateDir = function() end,
		IsDir = function() return false end,
	}

	env.AddCSLuaFile = function( path ) if path then gm.csFiles = gm.csFiles or {} gm.csFiles[ path ] = true end end

	env.include = function( path )
		local full = gm.root .. "/lua/" .. path
		local chunk, err = gm.loadfile( full )

		if not chunk then error( err, 2 ) end

		gm.included[ #gm.included + 1 ] = path

		return chunk()
	end

	env.CompileFile = function( path ) return gm.loadfile( gm.root .. "/lua/" .. path ) end

	-- сущности ---------------------------------------------------------------------------
	env.ents = {
		FindByClass = function( class )
			local out = {}

			for _, e in ipairs( gm.entities ) do
				if e:IsValid() and e:GetClass() == class then out[ #out + 1 ] = e end
			end

			return out
		end,
		FindInSphere = function() return {} end,
		GetAll = function() return gm.entities end,
		Create = function( class )
			if gm.entityFactory then return gm.entityFactory( class ) end

			return env.NULL
		end,
		Iterator = function() return ipairs( gm.entities ) end,
	}

	env.player = {
		GetAll = function() return gm.players or {} end,
		GetHumans = function() return gm.players or {} end,
		Iterator = function() return ipairs( gm.players or {} ) end,
	}

	-- DamageInfo: Set*/Get* по полям
	env.DMG_BLAST = 64
	env.DamageInfo = function()
		local d = { f = {} }

		return setmetatable( d, { __index = function( t, k )
			local field = k:sub( 4 )

			if k:sub( 1, 3 ) == "Set" then return function( self, v ) self.f[ field ] = v end end
			if k:sub( 1, 3 ) == "Get" then return function( self ) return self.f[ field ] end end
		end } )
	end

	-- GetGlobal2* / SetGlobal2*: одна таблица на мир, общая для сервера и клиента
	gm.globals = {}

	for _, kind in ipairs( { "Bool", "Int", "Float", "Vector", "Angle", "String", "Entity" } ) do
		env[ "GetGlobal2" .. kind ] = function( key, default )
			local v = gm.globals[ key ]

			if v == nil then return default end

			return v
		end
		env[ "SetGlobal2" .. kind ] = function( key, v ) gm.globals[ key ] = v end
		env[ "GetGlobal" .. kind ] = env[ "GetGlobal2" .. kind ]
		env[ "SetGlobal" .. kind ] = env[ "SetGlobal2" .. kind ]
	end

	env.scripted_ents = {
		GetStored = function() return nil end,
		Get = function() return nil end,
		Register = function() end,
		GetList = function() return {} end,
	}

	env.weapons = { GetStored = function() return nil end, Register = function() end }
	env.EffectData = function() return setmetatable( {}, { __index = function() return function() end end } ) end
	env.Sound = function( s ) return s end
	env.SoundDuration = function() return 1 end
	env.Material = function() return Void end
	env.Mesh = function() return Void end
	env.ScrW = function() return 1920 end
	env.ScrH = function() return 1080 end
	env.Lerp = function( t, a, b ) return a + ( b - a ) * t end
	env.LerpVector = function( t, a, b ) return a + ( b - a ) * t end
	env.LocalPlayer = function() return gm.localPlayer or env.NULL end
	env.ProtectedCall = function( fn, ... ) return pcall( fn, ... ) end

	-- клиентские библиотеки отрисовки: при загрузке файлов только регистрируются
	if realm == "client" then
		for _, name in ipairs( {
			"surface", "draw", "render", "cam", "vgui", "gui", "input", "notification", "language",
			"derma", "chat", "system", "matproxy", "halo", "killicon", "spawnmenu", "list",
			"ClientsideModel", "ParticleEmitter", "DermaMenu", "DrawColorModify", "Derma_Query",
			"Derma_StringRequest", "Derma_Message", "ScreenScale", "EyePos", "EyeAngles", "EyeVector",
			"GetRenderTarget", "CreateMaterial", "RenderType",
		} ) do
			env[ name ] = Void
		end

		env.vgui = setmetatable( {
			Register = function( name, tbl, base ) gm.panels = gm.panels or {} gm.panels[ name ] = { tbl = tbl, base = base } return tbl end,
			GetKeyboardFocus = function() return nil end,
			GetControlTable = function() return Void end,
			Create = function() return Void end,
			CreateFromTable = function() return Void end,
			CursorVisible = function() return false end,
			GetHoveredPanel = function() return nil end,
			GetWorldPanel = function() return Void end,
		}, { __index = function() return Void end } )

		env.surface = setmetatable( {
			CreateFont = function( name ) gm.fonts = gm.fonts or {} gm.fonts[ name ] = true end,
		}, { __index = function() return Void end } )

		env.input = setmetatable( {
			IsKeyDown = function() return false end,
			IsButtonDown = function() return false end,
			IsMouseDown = function() return false end,
			GetKeyName = function( k ) return "K" .. tostring( k ) end,
			LookupBinding = function() return nil end,
		}, { __index = function() return Void end } )

		env.gui = setmetatable( {
			IsGameUIVisible = function() return false end,
			IsConsoleVisible = function() return false end,
			MousePos = function() return 0, 0 end,
		}, { __index = function() return Void end } )
	end

	-- всё в _G -------------------------------------------------------------------------
	gm._installed = {}

	for k, v in pairs( env ) do
		G[ k ] = v
		gm._installed[ #gm._installed + 1 ] = k
	end

	G.SkyOps = nil
	gm._installed[ #gm._installed + 1 ] = "SkyOps"

	-- мир-сущность
	gm.world = gm.entity( { class = "worldspawn" } )

	function gm.world:GetModelBounds() return Vector( -16384, -16384, -16384 ), Vector( 16384, 16384, 16384 ) end

	-- неизвестные глобалы читаются как nil, но записываются в gm.unknownGlobals
	setmetatable( G, {
		__index = function( _, k )
			if not gm.KnownMissing[ k ] then gm.unknownGlobals[ k ] = ( gm.unknownGlobals[ k ] or 0 ) + 1 end
		end,
	} )
end

-- Препроцессор GLua (continue, !=, &&, ||, !, //, /* */) -> обычный Lua
gm.prep = dofile( ( debug.getinfo( 1, "S" ).source:match( "^@(.*[/\\])" ) or "./" ) .. "glua_prep.lua" )

function gm.loadfile( path )
	local f, err = io.open( path, "rb" )

	if not f then return nil, err end

	local src = f:read( "*a" )

	f:close()

	return loadstring( gm.prep( src ), "@" .. path )
end

function gm.include( path )
	return _G.include( path )
end

function gm.exists( path )
	local f = io.open( gm.root .. "/lua/" .. path )

	if f then f:close() return true end

	return false
end

-- Загрузка частей аддона в порядке загрузчика (sh_, sv_, cl_ внутри папки, по алфавиту).
-- dirs: { "skyops/core/", "skyops/arty/core/" }; файлы чужого реалма пропускаются.
function gm.loadDirs( dirs )
	_G.SkyOps = rawget( _G, "SkyOps" ) or {} -- обычно создаёт autorun/skyops_init.lua

	for _, dir in ipairs( dirs ) do
		local files = gm.ls( gm.root .. "/lua/" .. dir )

		table.sort( files )

		for _, prefix in ipairs( { "sh_", "sv_", "cl_" } ) do
			for _, name in ipairs( files ) do
				local own = prefix == "sh_" or ( prefix == "sv_" and gm.realm == "server" ) or ( prefix == "cl_" and gm.realm == "client" )

				if own and name:sub( 1, 3 ) == prefix and name:match( "%.lua$" ) then gm.include( dir .. name ) end
			end
		end
	end
end

-- Сущность-заглушка: таблица с NW2 и GetPos/GetAngles. Методы можно переопределять полями.
local ENT = {}
ENT.__index = ENT

function gm.entity( fields )
	local e = setmetatable( {
		__entity = true,
		class = "prop_physics",
		pos = Vector( 0, 0, 0 ),
		ang = Angle( 0, 0, 0 ),
		vel = Vector( 0, 0, 0 ),
		nw = {},
		valid = true,
	}, ENT )

	for k, v in pairs( fields or {} ) do e[ k ] = v end

	return e
end

function ENT:IsValid() return self.valid end
function ENT:Remove() self.valid = false end
function ENT:GetClass() return self.class end
function ENT:GetPos() return Vector( self.pos ) end
function ENT:SetPos( p ) self.pos = Vector( p ) end
function ENT:GetAngles() return Angle( self.ang ) end
function ENT:SetAngles( a ) self.ang = Angle( a ) end
function ENT:GetVelocity() return Vector( self.vel ) end
function ENT:GetForward() return self.ang:Forward() end
function ENT:EntIndex() return self.index or 1 end
function ENT:IsPlayer() return self.player == true end
function ENT:IsNPC() return false end
function ENT:GetTable() return self end
function ENT:Spawn() end
function ENT:Activate() end
function ENT:InvalidateBoneCache() end
function ENT:SetCreator( c ) self.creator = c end
function ENT:GetPhysicsObject() return self.phys or _G.NULL end
function ENT:LookupAttachment() return 0 end
function ENT:GetAttachment() return nil end
function ENT:ChatPrint( msg ) self.chat = self.chat or {} table.insert( self.chat, msg ) end
function ENT:IsAdmin() return true end

-- мировые углы сущности -> локальные (только поворот по yaw, без наклона корпуса)
function ENT:WorldToLocalAngles( a )
	return Angle( a.p - self.ang.p, math.NormalizeAngle( a.y - self.ang.y ), a.r - self.ang.r )
end

function ENT:LocalToWorldAngles( a )
	return Angle( a.p + self.ang.p, math.NormalizeAngle( a.y + self.ang.y ), a.r + self.ang.r )
end

for _, kind in ipairs( { "Bool", "Int", "Float", "Vector", "Angle", "String", "Entity" } ) do
	ENT[ "GetNW2" .. kind ] = function( self, key, default )
		local v = self.nw[ key ]

		if v == nil then return default end

		return v
	end

	ENT[ "SetNW2" .. kind ] = function( self, key, v ) self.nw[ key ] = v end
	ENT[ "GetNW" .. kind ] = ENT[ "GetNW2" .. kind ]
	ENT[ "SetNW" .. kind ] = ENT[ "SetNW2" .. kind ]
end

gm.ENT = ENT

-- Время --------------------------------------------------------------------------------

-- n кадров: двигает CurTime, срабатывают таймеры и хук Think
function gm.think( n, frame )
	frame = frame or gm.frame
	gm.frame = frame

	for _ = 1, n or 1 do
		gm.time = gm.time + frame

		for id, t in pairs( gm.timers ) do
			if t.at <= gm.time then
				if type( id ) == "number" then
					gm.timers[ id ] = nil
				elseif t.reps and t.reps ~= 0 then
					t.reps = t.reps - 1
					if t.reps == 0 then gm.timers[ id ] = nil else t.at = t.at + t.delay end
				else
					t.at = t.at + t.delay
				end

				t.fn()
			end
		end

		_G.hook.Run( "Think" )
		_G.hook.Run( "Tick" )
	end
end

gm.reset( "server" )

return gm
