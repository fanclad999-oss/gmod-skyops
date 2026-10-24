-- Artillery effects, server part: tells the clients about every shot, the flight of every
-- shell and every impact. All drawing and sounds are done by the clients (cl_fx), because
-- on InfMap a server-side effect or sound only reaches players in the same chunk, and the
-- point of these effects is to be seen and heard kilometres away.

local FX = SkyOps.Arty.FX
local B = SkyOps.Arty.Ballistics

util.AddNetworkString( "skyops_arty_fx_shot" )
util.AddNetworkString( "skyops_arty_fx_state" )
util.AddNetworkString( "skyops_arty_fx_impact" )

local STATE_PERIOD = 1 -- s between flight corrections

local cvTimeScale = GetConVar( "skyops_arty_timescale" )

local function NetId( shell )
	return shell.id % 65536
end

hook.Add( "SkyOps.Arty.ShellFired", "SkyOps.Arty.FX", function( shell )
	local pos = B.WorldPos( shell )
	local vel = B.WorldVel( shell )
	local spg = IsValid( shell.spg ) and shell.spg or NULL

	-- the 2S35 muzzle is a little off the shell start when the barrel moves; prefer it
	if IsValid( spg ) and SkyOps.Arty.FireComp.Muzzle then
		pos = SkyOps.Arty.FireComp.Muzzle( spg )
	end

	net.Start( "skyops_arty_fx_shot" )
		net.WriteUInt( NetId( shell ), 16 )
		net.WriteString( shell.shell )
		net.WriteEntity( spg )
		FX.WritePos( pos )
		FX.WritePos( vel:GetNormalized() )
		net.WriteFloat( cvTimeScale and cvTimeScale:GetFloat() or 1 )
		FX.WriteState( shell )
	net.Broadcast()
end )

hook.Add( "SkyOps.Arty.ShellRemoved", "SkyOps.Arty.FX", function( shell, reason )
	if reason ~= "impact" or not shell.impact then return end

	net.Start( "skyops_arty_fx_impact" )
		net.WriteUInt( NetId( shell ), 16 )
		net.WriteString( shell.shell )
		FX.WritePos( shell.impact )
	net.Broadcast()
end )

local NextState = 0

hook.Add( "Think", "SkyOps.Arty.FX", function()
	if CurTime() < NextState or next( B.Active ) == nil then return end

	NextState = CurTime() + STATE_PERIOD

	for _, shell in pairs( B.Active ) do
		net.Start( "skyops_arty_fx_state", true )
			net.WriteUInt( NetId( shell ), 16 )
			FX.WriteState( shell )
		net.Broadcast()
	end
end )
