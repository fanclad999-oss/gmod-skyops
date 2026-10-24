-- skyops_dump_lua: copies the Lua of SW Bombs missiles to data/skyops/dump/
-- so they can be read outside the game (the addon file itself is ~900 MB).

concommand.Add( "skyops_dump_lua", function( ply )
	if IsValid( ply ) and not ply:IsAdmin() then return end

	file.CreateDir( "skyops/dump" )
	local count = 0

	local function dump( path )
		local data = file.Read( path, "LUA" )
		if not data then return end
		file.Write( "skyops/dump/" .. string.gsub( path, "[/\\]", "__" ) .. ".txt", data )
		count = count + 1
	end

	local _, dirs = file.Find( "entities/sw_*", "LUA" )
	local files = file.Find( "entities/sw_*.lua", "LUA" )
	for _, f in ipairs( files ) do
		if string.find( f, "base", 1, true ) or string.find( f, "kh31", 1, true ) or string.find( f, "flare", 1, true ) then
			dump( "entities/" .. f )
		end
	end
	for _, d in ipairs( dirs ) do
		if string.find( d, "base", 1, true ) or string.find( d, "kh31", 1, true ) or string.find( d, "kh59", 1, true ) then
			for _, f in ipairs( file.Find( "entities/" .. d .. "/*.lua", "LUA" ) ) do
				dump( "entities/" .. d .. "/" .. f )
			end
		end
	end
	file.Write( "skyops/dump/_index.txt", table.concat( dirs, "\n" ) .. "\n--\n" .. table.concat( files, "\n" ) )

	print( "[SkyOps] dumped " .. count .. " files to data/skyops/dump" )
	if IsValid( ply ) then ply:ChatPrint( "SkyOps: сохранено файлов: " .. count ) end
end )
