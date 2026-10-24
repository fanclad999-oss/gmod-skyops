-- Minimal Garry's Mod server API mock, enough to run arty/core ballistics and arty/missions.
SERVER, CLIENT = true, false
local NOW = 0
function CurTime() return NOW end
function RealTime() return NOW end
function FrameTime() return 0.1 end
function SetTime( t ) NOW = t end
function AdvanceTime( dt ) NOW = NOW + dt end

-- Vector ---------------------------------------------------------------------------------
local VM = {}
VM.__index = VM
function Vector( x, y, z ) return setmetatable( { x = x or 0, y = y or 0, z = z or 0 }, VM ) end
VM.__add = function( a, b ) return Vector( a.x + b.x, a.y + b.y, a.z + b.z ) end
VM.__sub = function( a, b ) return Vector( a.x - b.x, a.y - b.y, a.z - b.z ) end
VM.__mul = function( a, b )
	if type( a ) == "number" then a, b = b, a end
	return Vector( a.x * b, a.y * b, a.z * b )
end
VM.__div = function( a, b ) return Vector( a.x / b, a.y / b, a.z / b ) end
VM.__unm = function( a ) return Vector( -a.x, -a.y, -a.z ) end
VM.__tostring = function( a ) return string.format( "Vector(%.1f %.1f %.1f)", a.x, a.y, a.z ) end
function VM:Length() return math.sqrt( self.x ^ 2 + self.y ^ 2 + self.z ^ 2 ) end
function VM:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
function VM:Distance( b ) return ( self - b ):Length() end
function VM:GetNormalized() local l = math.max( self:Length(), 1e-9 ) return self / l end
function VM:Dot( b ) return self.x * b.x + self.y * b.y + self.z * b.z end
function VM:Angle()
	return Angle( -math.deg( math.atan2( self.z, math.sqrt( self.x ^ 2 + self.y ^ 2 ) ) ), math.deg( math.atan2( self.y, self.x ) ), 0 )
end
function isvector( v ) return getmetatable( v ) == VM end
vector_origin = Vector( 0, 0, 0 )

local AM = {}
AM.__index = AM
function Angle( p, y, r ) return setmetatable( { p = p or 0, y = y or 0, r = r or 0 }, AM ) end
function AM:Forward()
	local p, y = math.rad( self.p ), math.rad( self.y )
	return Vector( math.cos( p ) * math.cos( y ), math.cos( p ) * math.sin( y ), -math.sin( p ) )
end
function AM:Right()
	local y = math.rad( self.y - 90 )
	return Vector( math.cos( y ), math.sin( y ), 0 )
end
angle_zero = Angle()

function Color( r, g, b, a ) return { r = r, g = g, b = b, a = a or 255 } end

-- helpers ----------------------------------------------------------------------------------
function isnumber( v ) return type( v ) == "number" end
function isstring( v ) return type( v ) == "string" end
function isfunction( v ) return type( v ) == "function" end
function istable( v ) return type( v ) == "table" end
function IsValid( e ) return e ~= nil and e ~= NULL and type( e ) == "table" and e.IsValid and e:IsValid() end
NULL = setmetatable( {}, { __index = function() return function() end end } )
function ErrorNoHalt( ... ) io.write( "ERR: ", ... ) end
function MsgC( ... ) end
function AddCSLuaFile() end
function SortedPairs( t )
	local keys = {}
	for k in pairs( t ) do keys[ #keys + 1 ] = k end
	table.sort( keys, function( a, b ) return tostring( a ) < tostring( b ) end )
	local i = 0
	return function() i = i + 1 local k = keys[ i ] if k ~= nil then return k, t[ k ] end end
end
function table.Copy( t ) local o = {} for k, v in pairs( t ) do o[ k ] = type( v ) == "table" and table.Copy( v ) or v end return o end
function table.Count( t ) local n = 0 for _ in pairs( t ) do n = n + 1 end return n end
function string.Trim( s ) return ( s:gsub( "^%s+", "" ):gsub( "%s+$", "" ) ) end
function math.Clamp( v, a, b ) return math.min( math.max( v, a ), b ) end
function math.Rand( a, b ) return a + ( b - a ) * math.random() end
function math.Round( n, d ) local m = 10 ^ ( d or 0 ) return math.floor( n * m + 0.5 ) / m end
function math.NormalizeAngle( a ) return ( a + 180 ) % 360 - 180 end
function os_date() return "" end

-- hooks --------------------------------------------------------------------------------------
local HOOKS = {}
hook = {}
function hook.Add( ev, id, fn ) HOOKS[ ev ] = HOOKS[ ev ] or {} HOOKS[ ev ][ id ] = fn end
function hook.Remove( ev, id ) if HOOKS[ ev ] then HOOKS[ ev ][ id ] = nil end end
function hook.Run( ev, ... )
	for _, fn in pairs( HOOKS[ ev ] or {} ) do
		local a, b = fn( ... )
		if a ~= nil then return a, b end
	end
end
function hook.GetTable() return HOOKS end

-- convars / commands -------------------------------------------------------------------------
CONVARS = {}
local CV = {}
CV.__index = CV
function CV:GetFloat() return tonumber( self.v ) or 0 end
function CV:GetInt() return math.floor( tonumber( self.v ) or 0 ) end
function CV:GetBool() return self:GetInt() ~= 0 end
function CV:GetString() return tostring( self.v ) end
function CreateConVar( name, def ) local c = setmetatable( { v = def }, CV ) CONVARS[ name ] = c return c end
function GetConVar( name ) return CONVARS[ name ] end
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 1, 2, 4
bit = bit or { bor = function( ... ) return 0 end }
COMMANDS = {}
concommand = { Add = function( name, fn ) COMMANDS[ name ] = fn end }
cvars = { AddChangeCallback = function() end }

-- net ----------------------------------------------------------------------------------------
NET_LOG = {}
local cur
net = {}
function net.Start( name ) cur = { name = name, data = {} } end
local function W( v ) cur.data[ #cur.data + 1 ] = v end
net.WriteString, net.WriteVector, net.WriteFloat, net.WriteEntity, net.WriteUInt, net.WriteData = W, W, W, W, W, W
function net.Send() NET_LOG[ #NET_LOG + 1 ] = cur end
net.Broadcast = net.Send
function net.Receive() end

util = {}
function util.AddNetworkString() end
function util.TableToJSON( t ) return "{}" end
function util.JSONToTable() return nil end
function util.Compress( s ) return s end
function util.Decompress( s ) return s end
function util.IsValidModel() return true end
function util.Effect() end
function util.BlastDamage() end
function util.TraceLine() return {} end
function EffectData() return { SetOrigin = function() end } end

FILES = {}
file = {
	CreateDir = function() end,
	Read = function( p ) return FILES[ p ] end,
	Write = function( p, s ) FILES[ p ] = s end,
	Find = function() return {}, {} end,
}

game = { SinglePlayer = function() return true end, GetWorld = function() return NULL end, GetMap = function() return "gm_infmap_kirovskoe" end }

-- entities ------------------------------------------------------------------------------------
ALL_ENTS = {}
local EM = {}
EM.__index = EM
function EM:IsValid() return not self.removed end
function EM:GetClass() return self.class end
function EM:SetPos( p ) self.pos = p end
function EM:GetPos() return self.pos end
function EM:SetAngles( a ) self.ang = a end
function EM:GetAngles() return self.ang or Angle() end
function EM:SetModel( m ) self.model = m end
function EM:Spawn() end
function EM:Activate() end
function EM:OBBMins() return Vector( -100, -40, 0 ) end
function EM:OBBMaxs() return Vector( 100, 40, 80 ) end
function EM:GetPhysicsObject() return { EnableMotion = function() end, Sleep = function() end, IsValid = function() return true end } end
function EM:Remove() self.removed = true end
function EM:SetColor( c ) self.color = c end
function EM:Ignite() self.burning = true end
function EM:SetCreator() end
function EM:Explode() end
function EM:GetNWVector( k, d ) return ( self.nw and self.nw[ k ] ) or d end
function EM:GetNW2Bool( k, d ) local v = self.nw2 and self.nw2[ k ] if v == nil then return d end return v end
function EM:GetNW2Int( k, d ) local v = self.nw2 and self.nw2[ k ] if v == nil then return d end return v end
function EM:GetNW2Float( k, d ) local v = self.nw2 and self.nw2[ k ] if v == nil then return d end return v end
function EM:SetNW2Bool( k, v ) self.nw2 = self.nw2 or {} self.nw2[ k ] = v end
EM.SetNW2Int, EM.SetNW2Float = EM.SetNW2Bool, EM.SetNW2Bool
function EM:GetDriver() return NULL end
function EM:GetHP() return self.hp or 1000 end
function EM:TakeDamage() self.tookDamage = true end

function MakeEnt( class ) local e = setmetatable( { class = class, pos = Vector() }, EM ) ALL_ENTS[ #ALL_ENTS + 1 ] = e return e end
STORED = { sw_2s35 = { t = {} }, sw_orlan10 = { t = { CatapultLaunchable = true } }, sw_uav_catapult = { t = {} } }
ents = {}
function ents.Create( class ) return MakeEnt( class ) end
function ents.FindByClass( class )
	local o = {}
	for _, e in ipairs( ALL_ENTS ) do if e.class == class and not e.removed then o[ #o + 1 ] = e end end
	return o
end
scripted_ents = { GetStored = function( c ) return STORED[ c ] end }

-- players
PLAYERS = {}
local PM = setmetatable( {}, { __index = EM } )
PM.__index = PM
function PM:Nick() return self.name end
function PM:IsAdmin() return true end
function PM:IsPlayer() return true end
function PM:EyeAngles() return Angle( 0, 90, 0 ) end
function PM:lvsGetVehicle() return self.vehicle end
function PM:PrintMessage( _, s ) print( "  > " .. s ) end
function MakePlayer( name ) local p = setmetatable( { name = name, class = "player", pos = Vector() }, PM ) PLAYERS[ #PLAYERS + 1 ] = p return p end
player = { GetHumans = function() return PLAYERS end, GetCount = function() return #PLAYERS end }
HUD_PRINTCONSOLE = 2

-- Kirovskoe-like terrain: 40 u/m, 60 x 60 km, gentle hills
KIR = { S = 40 }
local HALF = 30000 * 40
function KIR.MeshHeight( x, y )
	if math.abs( x ) > HALF or math.abs( y ) > HALF then return -math.huge end
	return ( 120 + 40 * math.sin( x / 40 / 3000 ) * math.cos( y / 40 / 2500 ) + 8 * math.sin( x / 40 / 300 ) ) * 40
end

SkyOps = { Teams = { BLUE = 1, RED = 2 }, Maps = { kirovskoe = { north_yaw = 90 } } }
