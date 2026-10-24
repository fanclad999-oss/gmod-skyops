-- SkyOps loader: includes every sh_/sv_/cl_ file under lua/skyops/,
-- core/ first, then the other folders in alphabetical order.

SkyOps = SkyOps or {}
SkyOps.Version = "0.1.0"

local ROOT = "skyops/"

local function LoadFile( path )
	local name = string.GetFileFromFilename( path )
	local prefix = string.sub( name, 1, 3 )

	if prefix == "sh_" then
		if SERVER then AddCSLuaFile( path ) end
		include( path )
	elseif prefix == "sv_" then
		if SERVER then include( path ) end
	elseif prefix == "cl_" then
		if SERVER then
			AddCSLuaFile( path )
		else
			include( path )
		end
	end
end

local function LoadFolder( dir )
	local files, folders = file.Find( dir .. "*", "LUA" )

	table.sort( files )
	-- shared first, then server, then client, so later files can rely on shared tables
	for _, prefix in ipairs( { "sh_", "sv_", "cl_" } ) do
		for _, name in ipairs( files ) do
			if string.sub( name, 1, 3 ) == prefix and string.EndsWith( name, ".lua" ) then
				LoadFile( dir .. name )
			end
		end
	end

	table.sort( folders )
	for _, sub in ipairs( folders ) do
		LoadFolder( dir .. sub .. "/" )
	end
end

LoadFolder( ROOT .. "core/" )

local _, folders = file.Find( ROOT .. "*", "LUA" )
table.sort( folders )
for _, sub in ipairs( folders ) do
	if sub ~= "core" then
		LoadFolder( ROOT .. sub .. "/" )
	end
end

hook.Run( "SkyOps.Loaded" )
