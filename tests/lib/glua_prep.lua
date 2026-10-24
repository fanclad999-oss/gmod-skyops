-- GLua -> Lua 5.1: переписывает синтаксис, который понимает только GMod, чтобы файл
-- загрузился в LuaJIT и прошёл luacheck. Строки и комментарии не трогает, номера строк
-- сохраняются.
--   continue  -> do end
--   !=  -> ~=      &&  -> and      ||  -> or      !x  -> not x
--   // комментарий -> --          /* ... */ -> --[[ ... ]]
--
-- Внимание: «continue» превращается в пустой оператор, поэтому код после него в той же
-- итерации выполнится. Для загрузки файлов в тестах этого хватает; поведение циклов с
-- continue тесты не проверяют.

local function prep( src )
	local out = {}
	local i, n = 1, #src

	local function emit( s ) out[ #out + 1 ] = s end

	while i <= n do
		local c = src:sub( i, i )
		local c2 = src:sub( i, i + 1 )

		if c2 == "--" then
			-- комментарий: длинный или до конца строки
			local eq = src:match( "^%[(=*)%[", i + 2 )

			if eq then
				local close = "]" .. eq .. "]"
				local e = src:find( close, i, true )
				local j = e and e + #close - 1 or n

				emit( src:sub( i, j ) )
				i = j + 1
			else
				local e = src:find( "\n", i, true ) or n + 1

				emit( src:sub( i, e - 1 ) )
				i = e
			end
		elseif c2 == "//" then
			local e = src:find( "\n", i, true ) or n + 1

			emit( "--" .. src:sub( i + 2, e - 1 ) )
			i = e
		elseif c2 == "/*" then
			local e = src:find( "*/", i + 2, true )
			local body = src:sub( i + 2, ( e or n + 1 ) - 1 ):gsub( "%]%]", "] ]" )

			emit( "--[==[" .. body .. "]==]" )
			i = e and e + 2 or n + 1
		elseif c == "[" and src:match( "^%[=*%[", i ) then
			local eq = src:match( "^%[(=*)%[", i )
			local close = "]" .. eq .. "]"
			local e = src:find( close, i, true )
			local j = e and e + #close - 1 or n

			emit( src:sub( i, j ) )
			i = j + 1
		elseif c == '"' or c == "'" then
			local j = i + 1

			while j <= n do
				local d = src:sub( j, j )

				if d == "\\" then
					j = j + 2
				elseif d == c or d == "\n" then
					break
				else
					j = j + 1
				end
			end

			emit( src:sub( i, j ) )
			i = j + 1
		elseif c2 == "!=" then
			emit( "~=" )
			i = i + 2
		elseif c2 == "&&" then
			emit( " and " )
			i = i + 2
		elseif c2 == "||" then
			emit( " or " )
			i = i + 2
		elseif c == "!" then
			emit( " not " )
			i = i + 1
		elseif c:match( "[%a_]" ) then
			local word = src:match( "^[%w_]+", i )

			if word == "continue" and not src:sub( i - 1, i - 1 ):match( "[%.:]" ) then
				emit( "do end" )
			else
				emit( word )
			end

			i = i + #word
		elseif c:match( "%d" ) then
			-- число целиком, чтобы «1e5» не разбирался как слово
			local num = src:match( "^0[xX]%x+", i ) or src:match( "^%d+%.?%d*[eE][%+%-]?%d+", i ) or src:match( "^%d+%.?%d*", i )

			emit( num )
			i = i + #num
		else
			emit( c )
			i = i + 1
		end
	end

	return table.concat( out )
end

return prep
