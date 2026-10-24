-- Artillery supply, shared part: the 2S35 carries a limited load of shells by type, a
-- supply vehicle (KamAZ-5350 from Workshop 3198481596, or our ammo crate as a fallback)
-- brings more. sv_supply does the counting and the transfer, cl_supply the HUD.
--
-- NW2 on sw_2s35:
--   SkyOpsArty_Ammo_<shell> (int)    rounds of that shell in the gun
--   SkyOpsArty_Order_<shell> (int)   rounds of that shell the crew wants after resupply
--   SkyOpsArty_Resupply (entity)     the carrier passing rounds right now, or NULL
-- NW2 on a carrier (truck or crate):
--   SkyOpsArty_Stock (int)           rounds in the body
--   SkyOpsArty_Supplying (entity)    the 2S35 it is loading right now, or NULL

SkyOps.Arty = SkyOps.Arty or {}
SkyOps.Arty.Supply = SkyOps.Arty.Supply or {}

local S = SkyOps.Arty.Supply

local FLAGS = bit.bor( FCVAR_ARCHIVE, FCVAR_REPLICATED )

S.cvLimit = CreateConVar( "skyops_arty_ammo_limit", "1", FLAGS, "1 = the 2S35 has a limited load and needs resupply, 0 = endless shells", 0, 1 )
S.cvCapacity = CreateConVar( "skyops_arty_ammo_cap", "40", FLAGS, "Rounds the 2S35 carries", 1, 200 )
S.cvCarriers = CreateConVar( "skyops_arty_supply_classes", "sw_kamaz5350", FLAGS, "Comma separated vehicle classes that carry shells (prefix match)" )

S.CRATE_CLASS = "skyops_arty_ammocrate"
S.RANGE = 15 -- m between the gun and the carrier
S.MAX_SPEED = 1 -- m/s, both must stand still

-- load of a fresh gun, for capacity 40; other capacities scale it
S.DEFAULT_LOAD = { he = 28, krasnopol = 6, smoke = 3, illum = 2, cluster = 1 }

local function FC() return SkyOps.Arty.FireComp end

function S.Enabled()
	return S.cvLimit:GetBool()
end

function S.Capacity()
	return S.cvCapacity:GetInt()
end

-- shell ids in display order: FireComp.ShellOrder when the core has it, else he first
function S.Shells()
	local fc = FC()

	if fc and fc.ShellOrder then return fc.ShellOrder end

	local list = {}

	for id in pairs( fc and fc.Shells or S.DEFAULT_LOAD ) do list[ #list + 1 ] = id end

	table.sort( list, function( a, b )
		if a == "he" or b == "he" then return a == "he" end

		return a < b
	end )

	return list
end

function S.ShellName( id )
	local fc = FC()
	local def = fc and fc.Shells and fc.Shells[ id ]

	return def and ( def.short or def.name ) or id
end

-- shell now in the breech: the core's NW2 choice, or the stock ShellType
function S.LoadedShell( spg )
	local fc = FC()

	if fc and fc.LoadedShell then return fc.LoadedShell( spg ) end
	if fc and fc.ShellForStockType then return fc.ShellForStockType( spg.GetShellType and spg:GetShellType() or 0 ) end

	return "he"
end

function S.Count( spg, id )
	return spg:GetNW2Int( "SkyOpsArty_Ammo_" .. id, 0 )
end

function S.Ordered( spg, id )
	return spg:GetNW2Int( "SkyOpsArty_Order_" .. id, 0 )
end

function S.Total( spg )
	local n = 0

	for _, id in ipairs( S.Shells() ) do n = n + S.Count( spg, id ) end

	return n
end

-- the default load scaled to the capacity: { [id] = rounds }, only shells the core knows
function S.DefaultLoad()
	local cap = S.Capacity()
	local base, known = 0, {}

	for _, id in ipairs( S.Shells() ) do
		local n = S.DEFAULT_LOAD[ id ] or 0

		known[ id ] = n
		base = base + n
	end

	local load, used = {}, 0

	for id, n in pairs( known ) do
		load[ id ] = base > 0 and math.floor( n * cap / base ) or 0
		used = used + load[ id ]
	end

	load.he = ( load.he or 0 ) + cap - used

	return load
end

function S.IsCarrier( ent )
	if not IsValid( ent ) then return false end

	local class = ent:GetClass()

	if class == S.CRATE_CLASS then return true end

	for prefix in string.gmatch( S.cvCarriers:GetString(), "[^,%s]+" ) do
		if string.StartWith( class, prefix ) then return true end
	end

	return false
end

-- Fallback carrier: an ammo crate from the spawn menu (SkyOps category) -----------------

local ENT = {}

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Ящики со снарядами 152 мм"
ENT.Category = "SkyOps"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.Model = "models/items/ammocrate_rockets.mdl"

if SERVER then
	function ENT:SpawnFunction( ply, tr, class )
		if not tr.Hit then return end

		local ent = ents.Create( class )

		ent:SetPos( tr.HitPos + tr.HitNormal * 20 )
		ent:SetAngles( Angle( 0, ply:EyeAngles().y + 180, 0 ) )
		ent:Spawn()
		ent:Activate()

		return ent
	end

	function ENT:Initialize()
		self:SetModel( self.Model )
		self:PhysicsInit( SOLID_VPHYSICS )
		self:SetMoveType( MOVETYPE_VPHYSICS )
		self:SetSolid( SOLID_VPHYSICS )
		self:SetUseType( SIMPLE_USE )

		local phys = self:GetPhysicsObject()

		if IsValid( phys ) then phys:Wake() end

		if S.InitCarrier then S.InitCarrier( self ) end
	end

	function ENT:Use( ply )
		if S.TellStock then S.TellStock( self, ply ) end
	end
end

scripted_ents.Register( ENT, S.CRATE_CLASS )
