spoon = require("spoon")

local function printableTable(w, t, s, p)
	if type(w) == 'table' then
		p = s; s = t; t = w; w = nil
	end
	s = s or ' '
	local r
	local g = true
	if not w then
		r = ''
		g = false
	elseif w == '' then
		r = 'Table ='
	else r = 'Table['..w..'] ='
	end
	if type(t) == 'table' then
		local function addValue(k,v)
			if type(v) == 'number' then
				local w, f = math.modf(v)
				if f ~= 0 then
					v = string.format('%.3f', v)
				end
			end
			if g or p then r = r..s else g = true end
			r = r..tostring(k)..'='..tostring(v)
		end
		local did = {}
		for k, v in ipairs(t) do	-- put the contiguous numerics in first
			did[k] = true
			addValue(k,v)
		end
		local f = nil	-- Comparison function?
		local a = {}
		for n in pairs(t) do	-- and now the non-numeric
			if not did[n] then
				table.insert(a, tostring(n))
			end
		end
		table.sort(a, f)
		for i, k in ipairs(a) do
			addValue(k,t[k])
		end
	else	r = r..' '..type(t)..'('..tostring(t)..')'
	end
	return r
end

local function showFolderContents(token)

		local stream = MOAIMemStream.new ()
		stream:open ( )

		local function postComplete( task, responseCode )
			local streamSize = stream:getLength()

			if responseCode ~= 200 then
				print ( "postComplete:Network error:"..responseCode)
			elseif streamSize == 4294967295 then
				print ( "postComplete:Size:"..streamSize)
			else
				stream:seek(0)
				local content, readbytes = stream:read()
				print("Response: "..content)
				local j = MOAIJsonParser.decode(content)
				print("Or: "..printableTable(j,"\r\n"))
				for k,e in pairs(j.entries) do
					print(printableTable("entries["..tostring(k).."]", e,"\r\n"))
				end
				for k,e in pairs(j.entries) do
					print(tostring(e[".tag"]).."["..tostring(k).."]:"..tostring(e.path_display))
				end
			end
		end

--		local t = { path="/*", recursive=false, include_media_info=false, include_deleted=false, include_has_explicit_shared_members=false }
--		local t = { path="", recursive=false }
--		local t = { path="", recursive=true }
--		local t = { path="/2017BikeMSCitrusTour", recursive=true }
		local t = { path="/2017BikeMSCitrusTour", recursive=true }
		t = MOAIJsonParser.encode(t)
		print("Sending:"..t)

		local task = MOAIHttpTask.new ()
		task:setVerb ( MOAIHttpTask.HTTP_POST )
		task:setUrl ( "https://api.dropboxapi.com/2/files/list_folder" )
		task:setBody ( t )
		task:setHeader ( "Authorization", "Bearer "..token )
		task:setHeader ( "Content-Type", "application/json" )
		task:setStream ( stream )
		task:setTimeout ( 30 )
		task:setCallback ( postComplete )
		task:setUserAgent ( string.format('APRSISMO') )
		task:setVerbose ( false )
		task:performAsync ()

	local me = MOAICoroutine:currentThread()
	if me then
	  print("Running under MOAICoroutine, yielding isBusy")
	  while task:isBusy() do
--			local start = MOAISim.getDeviceTime()
		    coroutine.yield(server)
--			local elapsed = (MOAISim.getDeviceTime() - start) * 1000
--			print(string.format("yield took %.2fmsec", elapsed))
	  end
	else
	  print("Not running on MOAICoroutine, performSynch")
		task:performSync ()
    end
	print("showFolderContents complete!")

end

local function GET(opt, req)

	print("GET "..tostring(req.puri.path))

	if req.puri.path == "/favicon.ico" then
		local inp = io.open("APRSISMO.ico", "rb")
		if inp then
			local content = inp:read("*all")
			inp:close()
			return spoon.response(200, content, "image/x-icon")
		else
			return spoon.Errorpage(404, "No "..tostring(req.puri.path).." on this server")
		end
	elseif req.puri.path == "/icon-google.png" then
		local inp = io.open("icon-google.png", "rb")
		if inp then
			local content = inp:read("*all")
			inp:close()
			return spoon.response(200, content, "image/png")
		else
			return spoon.Errorpage(404, "No "..tostring(req.puri.path).." on this server")
		end
	elseif req.puri.path == "/APRSISMO.code" then

--[[
https://api.dropboxapi.com/oauth2/token
code=DXkqwNYZX-gAAAAAAAAXzkpqmHXCyNhfj4wZkCi_5Lw
grant_type=authorization_code
client_id=f2xxipuqrcaytsu
client_secret=n7a86vnm3o6kmbg
redirect_uri=http://localhost:8080/APRSISMO.code
]]
		local stream = MOAIMemStream.new ()
		stream:open ( )

		local oauth2_token
		
		local function postComplete( task, responseCode )
			local streamSize = stream:getLength()

			if responseCode ~= 200 then
				print ( "postComplete:Network error:"..responseCode)
			elseif streamSize == 4294967295 then
				print ( "postComplete:Size:"..streamSize)
			else
				stream:seek(0)
				local content, readbytes = stream:read()
				print("Response: "..content)
				oauth2_token = MOAIJsonParser.decode(content)
				print("Or: "..printableTable(oauth2_token,"\r\n"))
			end
		end

		local t = ""
		t = t .. "code="..req.puri.pquery.code
		t = t .. "&grant_type=authorization_code"
		t = t .. "&client_id=f2xxipuqrcaytsu"
		t = t .. "&client_secret=n7a86vnm3o6kmbg"
		t = t .. "&redirect_uri=http://localhost:8080/APRSISMO.code"

		local task = MOAIHttpTask.new ()
		task:setVerb ( MOAIHttpTask.HTTP_POST )
		task:setUrl ( "https://api.dropboxapi.com/oauth2/token" )
		task:setBody ( t )
		task:setStream ( stream )
		task:setTimeout ( 30 )
		task:setCallback ( postComplete )
		task:setUserAgent ( string.format('APRSISMO') )
		task:setVerbose ( false )
		task:performSync ()
		if oauth2_token then
		
MOAICoroutine.new ():run ( function()
								showFolderContents(oauth2_token.access_token)
							end)
		
			return spoon.response(200, string.format("<H1>Access Token Acquired</H1><ul>%s</ul>",
									printableTable(oauth2_token,"<li>",true)))
		else
			return spoon.response(200, string.format("<H1>Nothing To See Here</H1><p>But here's what you told me!</p><table border><tr><td>Opt<td>%s<tr><td>Req<td>%s<tr><td>Method<td>%s<tr><td>URI<td>%s<tr><td>Ver<td>%s<tr><td>Headers<td>%s<tr><td>puri<td>%s<tr><td>puri.ppath<td>%s<tr><td>puri.pquery<td>%s",
									printableTable(opt,"<BR>"), printableTable(req,"<BR>"),
									tostring(req.method), tostring(req.uri), tostring(req.httpver),
									printableTable(req.headers,"<BR>"), printableTable(req.puri,"<BR>"),
									printableTable(req.puri.ppath,"<BR>"), printableTable(req.puri.pquery,"<BR>")))
		end
	else
		return spoon.response(200, string.format("<H1>Nothing To See Here</H1><p>But here's what you told me!</p><table border><tr><td>Opt<td>%s<tr><td>Req<td>%s<tr><td>Method<td>%s<tr><td>URI<td>%s<tr><td>Ver<td>%s<tr><td>Headers<td>%s<tr><td>puri<td>%s<tr><td>puri.ppath<td>%s<tr><td>puri.pquery<td>%s",
								printableTable(opt,"<BR>"), printableTable(req,"<BR>"),
								tostring(req.method), tostring(req.uri), tostring(req.httpver),
								printableTable(req.headers,"<BR>"), printableTable(req.puri,"<BR>"),
								printableTable(req.puri.ppath,"<BR>"), printableTable(req.puri.pquery,"<BR>")))
	end
end

MOAISim.openWindow ( "test", 320, 480 )

--[[
main = function ()

	MOAICoroutine.new ():run ( true, function () print ( 'thread1' ) end )
	MOAICoroutine.new ():run ( false, function () print ( 'thread2' ) end )

	MOAICoroutine.new ():run ( true, function ()

		print ( 'thread3' )

		MOAICoroutine.new ():run ( true, function () print ( 'thread4' ) end )
		MOAICoroutine.new ():run ( false, function () print ( 'thread5' ) end )

	end )

	coroutine.yield ()
	print ( 'step 2' )

	coroutine.yield ()
	print ( 'step 3' )

end
]]

MOAICoroutine.new ():run ( function()
								spoon.debug = false
								spoon.spoon({verbose=false, loop=true, GET=GET})
							end)
							
MOAICoroutine.new ():run ( function ()
								if spoon.port then
									print("Spoon.port="..tostring(spoon.port))
								else 
									coroutine.yield()
								end
							end )
							
--MOAICoroutine.new ():run ( function()
--								showFolderContents("DXkqwNYZX-gAAAAAAAAYG_3Y2ZtDLqbiYMhv5mhF_K_CudHoq4hwThRU_Qdj5iXb")
--							end)

--DXkqwNYZX-gAAAAAAAAYG_3Y2ZtDLqbiYMhv5mhF_K_CudHoq4hwThRU_Qdj5iXb
