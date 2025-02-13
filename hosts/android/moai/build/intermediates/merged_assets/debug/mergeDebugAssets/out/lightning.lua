local M = {version="0.0.1"}

local toast = require("toast");
local APRS = require("APRS")
local stationList = require("stationList")

module(..., package.seeall)

local lastID = {}
local lsObjects = nil
local lightnings = nil
local gridSquares = {}
local strikeSquares = {}

local pendingZones, pendingZones2, pendingStrikes, pendingKills = {}, {}, {}, {}

local header = 'KJ4ERJ-LS>APZLUA,TCPIP*:'

local tGSActive, tStrikeActive, tGSDelta, tStrikeDelta, tPackets = 0, 0, 0, 0, 0
local tLZActive, tLZDelta = 0, 0

local telem = require('telemetry')
telem:definePoint("GridSquares", "active", 0,1,0, function() return tGSActive end)
telem:definePoint("Strikes", "active", 0,5,0, function() return tStrikeActive end)
telem:definePoint("StrikeSquares", "active", 0,4,0, function() return tLZActive end)
--telem:definePoint("GridSquares", "net delta", 0,2,-128, function() local t=tGSDelta tGSDelta=0 tLZDelta=0 return t end)
telem:definePoint("Strikes", "net delta", 0,4,-256, function() local t=tStrikeDelta tStrikeDelta=0 tGSDelta=0 tLZDelta=0 return t end)
telem:definePoint("Pkts Sent", "2 min", 0,10,0, function() local t=tPackets tPackets=0 return t end)
--telem:defineBit("Bit0", "on", 1, function() return 1 end)
telem:init('Lightning Stats',120, header)

local msLoop = 62
local skipped = false
performWithDelay(msLoop, function()	-- Was 125 prior to 5/24/2017
	local pending = #pendingZones + #pendingZones2 + #pendingStrikes + #pendingKills
	local timeNeeded = msLoop * pending * 2	-- The *2 is to account for skipping every other loop
	if skipped or timeNeeded > 60*1000 then	-- If there's more than 1 minute queued at the slow rate
		local p = table.remove(pendingZones,1)
		if not p then p = table.remove(pendingZones2) end
		if not p then p = table.remove(pendingStrikes) end
		if not p then p = table.remove(pendingKills) end
		if p then
			--print("Sending:"..p)
			local status = APRSIS:sendPacket(p)
			if status then print("APRSIS FAILED to send "..p) end
			tPackets = tPackets + 1
		end
		skipped = false;
	else skipped = true
	end
end, 0)

local function tableCount(t)
	local c = 0
	for _, _ in pairs(t) do
		c = c + 1
	end
	return c
end
local function ToXmlString(value)
	value = string.gsub (value, "&", "&amp;");         -- '&' -> "&"
	value = string.gsub (value, "<", "&lt;");               -- '<' -> "<"
	value = string.gsub (value, ">", "&gt;");               -- '>' -> ">"
	value = string.gsub (value, "\"", "&quot;");    -- '"' -> """
	value = string.gsub(value, "([^%w%&%;%p%\t% ])",
		function (c)
				return string.format("&#x%X;", string.byte(c))
		end);
	return value;
end
local function writeXmlTable(hFile, tag, values)
--print('writeXmlTable(tag:'..tostring(tag)..' values:'..tostring(values)..')')
	hFile:write('<'..tag..'>\n')
	local k,v
	for k,v in pairs(values) do
		if type(v) == 'string' or type(v) == 'number' or type(v) == 'boolean' then
			hFile:write('<'..k..'>', ToXmlString(tostring(v)), '</'..k..'>\n')
		elseif type(v) == 'table' then
			if k ~= '__special' then
				if #v == tableCount(v) then
					local i
					for i = 1, #v do
						if type(v[i]) == 'table' then
							writeXmlTable(hFile, k, v[i])
						elseif type(v[i]) == 'string' or type(v[i]) == 'number' or type(v[i]) == 'boolean' then
							hFile:write('<'..k..'>', ToXmlString(tostring(v[i])), '</'..k..'>\n')
						else	print('unsupport type('..k..')('..type(v)..')')
						end
					end
				else
					writeXmlTable(hFile, k, v)
				end
			end
		elseif type(v) == 'function' then	-- ignore these
		else	print('unsupport type('..k..')('..type(v)..')')
		end
	end
	hFile:write('</'..tag..'>\n')
end

local function save(tToSave, file, dir)

	local safePath = system.pathForFile( file..'-Safe', dir )
	local realPath = system.pathForFile( file, dir )
	local outputPath = system.pathForFile( file..'-Temp', dir )
	local hFile, err = io.open(outputPath, "w")

	tToSave.LastSaved = os.date('!%Y-%m-%dT%H:%M:%S')

	if hFile and not err then
		local _,_,prefix = string.find(file, '(.+)%.')
		prefix = prefix or file	-- Just the outer XML element name
		writeXmlTable(hFile, prefix, tToSave)
		io.close(hFile)
		print('Saved To '..file)
		local safePath = system.pathForFile( file..'-Safe', dir )
		os.remove(safePath)
		os.rename(realPath, safePath)
		os.rename(outputPath, realPath)
		return true
	else
		print('Failed to save to '..outputPath)
		print( err )
		return false
	end
	configChanged = false	-- reset the changed flag
end

local function load(file, dir)
	local xmlapi = require( "xml" ).newParser()
	local safePath = system.pathForFile( file..'-Safe', dir )
	local realPath = system.pathForFile( file, dir )
	local configXML = xmlapi:loadFile( file, dir )
	if not configXML then
		print('Failed To load from '..file..' in '..dir)
		configXML = xmlapi:loadFile( file..'-Safe', dir )
	end
	
	if configXML then
		print('Loaded from '..file..' in directory '..dir)
		return xmlapi:simplify( configXML )
	else
		print('Failed to load '..file..' from '..dir)
		return {}
	end
end

lightnings = load('lightnings.xml','.')
lsObjects = {}
if lightnings then
	local tNow = os.date("!*t")
	tNow.isdst = nil
	tNow = os.time(tNow)
	for i,o in pairs(lightnings) do
		if type(o) == 'table' and o.timestamp then
--			print('lightning recalling '..i.." "..tostring(o.timestamp).." "..tostring(o.time))
			lsObjects[o.timestamp] = o
			o.time = tonumber(o.time)

		if not gridSquares[o.GS] then
			gridSquares[o.GS] = {} print("Created GS:"..o.GS)
		end
		gridSquares[o.GS][o.timestamp] = o
		gridSquares[o.GS].updated = tNow

		if not strikeSquares[o.LS] then
			strikeSquares[o.LS] = {} print("Created LS:"..o.LS)
		end
		strikeSquares[o.LS][o.timestamp] = o
		strikeSquares[o.LS].updated = tNow

		else print("lightnings:Ignoring "..tostring(i).."="..tostring(s))
		end
	end
end

function M:killOld(age)
	local lsActiveCount, lsKillCount, gsActiveCount, gsSentCount, gsKillCount = 0, 0, 0, 0, 0
	local lzActiveCount, lzSentCount, lzKillCount = 0, 0, 0
	local tNow = os.date("!*t")
	tNow.isdst = nil
	tNow = os.time(tNow)
	local tOld = tNow - age
	local kills = {}
	for i, o in pairs(lightnings) do
		if (type(o) == 'table') and o.time then
			if o.time <= tOld then
				lsObjects[o.timestamp] = nil
				if o.GS and gridSquares[o.GS] then
					gridSquares[o.GS][o.timestamp] = nil
					gridSquares[o.GS].updated = tNow
				end
				if o.LS and strikeSquares[o.LS] then
					strikeSquares[o.LS][o.timestamp] = nil
					strikeSquares[o.LS].updated = tNow
				end
				kills[i] = o
			else lsActiveCount = lsActiveCount + 1
			end
		else
			if type(o) == 'table' then
				print("lightnings:Ignoring "..printableTable(i,o))
			else print("lightnings:Ignoring "..tostring(i).."="..tostring(o))
			end
		end
	end

	local tm = os.date('!*t')
	for i, o in pairs(kills) do
--		local tm = os.date('*t', o.time)
		local killPacket = header..APRS:ObjectHHMMSS(o.ID, tm.hour, tm.min, tm.sec,
									{lat=o.lat, lon=o.lon, symbol='\\J', comment="Expired"}, true)
--		local killPacket = (o.packet:gsub("%*","_",2)):gsub("_","%*",1)
--		print("Orig:"..o.packet)
--		print("Kill:"..tostring(killPacket))
		if killPacket then
			stationList.packetReceived(killPacket)	-- remove it from our local map
			-- table.insert(pendingKills,killPacket)	-- No longer transmit kills (or the original objects)
			lightnings[i] = nil
			lsKillCount = lsKillCount + 1
		end
		tStrikeDelta = tStrikeDelta - 1
	end

	kills = {}
	for g,t in pairs(gridSquares) do
		if type(t) == "table"	then
			gsActiveCount = gsActiveCount + 1
			if not t.lastSent or t.updated > t.lastSent then
				local lat, lon = 0, 0
				local glat, glon = APRS:GridSquare2LatLon(g)
				local count = 0
				for ts,o in pairs(t) do
					if type(o) == "table" and o.lat and o.lon then
						lat, lon = lat+o.lat, lon+o.lon
						count = count + 1
					end
				end
		--		print(g.." has "..tostring(count).." strikes")
				if count == 0 then table.insert(kills,g) end

				local ID = 'SZ-'..g
				if count > 0 then
					lat, lon = lat/count, lon/count
				else lat, lon = glat, glon
				end
					local s = {}
					local offset = 180/18/10	-- for 4 character gridsquare
					table.insert(s,{lat=glat-offset/2,lon=glon-offset})
					table.insert(s,{lat=glat+offset/2,lon=glon-offset})
					table.insert(s,{lat=glat+offset/2,lon=glon+offset})
					table.insert(s,{lat=glat-offset/2,lon=glon+offset})
					table.insert(s,{lat=glat-offset/2,lon=glon-offset})
					local scale = 2/44	-- Was 0.1
					local temp = string.char(math.floor(math.log10(scale/.0001)*20+0.9999)+33)
					scale = math.pow(10,(temp:byte()-33)/20.0)*0.0001
					for i,p in ipairs(s) do
						local latOff, lonOff = math.floor((p.lat-lat)/scale+0.5), math.floor((lon-p.lon)/scale+0.5)
						temp = temp..string.char(latOff+78, lonOff+78)
					end
				--	print("Resulting Multi:"..temp.." vs:IXSXSDIDIX")
						
				local comment = tostring(count).." strikes }d1"..temp.."{!W00!"
				local packet = header..APRS:ObjectHHMMSS(ID, tm.hour, tm.min, tm.sec,
													{lat=lat, lon=lon, symbol='\\T', comment=comment}, (count==0))
				stationList.packetReceived(packet)	-- put it on our local map
				table.insert(pendingZones,packet)
				t.packet = packet
				if count == 0 then
					gsKillCount = gsKillCount + 1
				else gsSentCount = gsSentCount + 1
				end
				t.lastSent = tNow
		--	else print(tostring(g).." "..tostring(t.lastSent)..">="..tostring(t.updated))
			end
		else print("Skipping ["..tostring(g).."]="..tostring(t))
		end
	end

	for i, g in pairs(kills) do
		gridSquares[g] = nil
		tGSDelta = tGSDelta - 1
	end

	save(gridSquares, 'gridsquares.xml','.')
	
	kills = {}
	for g,t in pairs(strikeSquares) do
		if type(t) == "table"	then
			lzActiveCount = lzActiveCount + 1
			if not t.lastSent or t.updated > t.lastSent then
				local lat, lon = 0, 0
				local glat, glon = APRS:GridSquare2LatLon(g)
				local count = 0
				local strike = nil
				for ts,o in pairs(t) do
					if type(o) == "table" and o.lat and o.lon then
						lat, lon = lat+o.lat, lon+o.lon
						count = count + 1
						strike = o
					end
				end
		--		print(g.." has "..tostring(count).." strikes")
				if count == 0 then table.insert(kills,g) end

				local ID = 'LS-'..g
				if count > 0 then
					lat, lon = lat/count, lon/count
				else lat, lon = glat, glon
				end
				
				local packet
				local emptyMultiLine = " }l1!NN{!W00!"
				if count == 1 and strike ~= nil then
					packet = header..APRS:ObjectHHMMSS(ID, strike.hour, strike.minute, strike.second,
														{lat=strike.lat, lon=strike.lon,
														symbol='\\J', comment=strike.comment..emptyMultiLine})
					table.insert(pendingZones2,packet)
					lzSentCount = lzSentCount + 1
				elseif count == 0 then
					packet = header..APRS:ObjectHHMMSS(ID, tm.hour, tm.min, tm.sec,
													{lat=lat, lon=lon, symbol='\\J',
													comment="Expired"..emptyMultiLine}, (count==0))
					table.insert(pendingKills,packet)
					lzKillCount = lzKillCount + 1
				else
					local s = {}
					local offset = 180/18/10/24	-- for 6 character gridsquare
					table.insert(s,{lat=glat-offset/2,lon=glon-offset})
					table.insert(s,{lat=glat+offset/2,lon=glon-offset})
					table.insert(s,{lat=glat+offset/2,lon=glon+offset})
					table.insert(s,{lat=glat-offset/2,lon=glon+offset})
					table.insert(s,{lat=glat-offset/2,lon=glon-offset})
					local scale = 2/44/24	-- Was 0.1
					local temp = string.char(math.floor(math.log10(scale/.0001)*20+0.9999)+33)
					scale = math.pow(10,(temp:byte()-33)/20.0)*0.0001
					for i,p in ipairs(s) do
						local latOff, lonOff = math.floor((p.lat-lat)/scale+0.5), math.floor((lon-p.lon)/scale+0.5)
						temp = temp..string.char(latOff+78, lonOff+78)
					end
				--	print("Resulting Multi:"..temp.." vs:IXSXSDIDIX")
					local symbol = "\\J"
					if count > 9 then
						symbol = "9J"
						temp = "}a0"..temp.."{!W00!"	-- Color and fill the box red for >9
					else
						symbol = tostring(count).."J"
						if count > 5 then
							temp = "}d0"..temp.."{!W00!"	-- filled yellow is Severe Thunderstorm Warning
						else temp = "}d1"..temp.."{!W00!"	-- yellow is Severe Thunderstorm Warning
						end
					end
					comment = tostring(count).." strikes "..temp
					packet = header..APRS:ObjectHHMMSS(ID, tm.hour, tm.min, tm.sec,
													{lat=lat, lon=lon, symbol=symbol, comment=comment}, (count==0))
					table.insert(pendingZones2,packet)
					lzSentCount = lzSentCount + 1
				end
				stationList.packetReceived(packet)	-- put it on our local map
				t.packet = packet

				t.lastSent = tNow
		--	else print(tostring(g).." "..tostring(t.lastSent)..">="..tostring(t.updated))
			end
		else print("Skipping ["..tostring(g).."]="..tostring(t))
		end
	end

	for i, g in pairs(kills) do
		strikeSquares[g] = nil
		tLZDelta = tLZDelta - 1
	end

	save(strikeSquares, 'strikesquares.xml','.')
	
	return lsActiveCount, lsKillCount, gsActiveCount, gsSentCount, gsKillCount, lzActiveCount, lzSentCount, lzKillCount
	--if killCount > 0 then toast.new('Killed '..tostring(killCount)..' Old Lightnings', 5000) end
end

local charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
local charcount = #charset

local function getChar(n)
	local prefix = ''
	n = tonumber(n)
	if n >= charcount then
		prefix = getChar(math.floor(n/charcount))
		n = n%charcount
	end
	return prefix..charset:sub(n+1,n+1)
end

function M:parse(text, source)
	local count, newCount = 0, 0
	local tNow = os.date("!*t")
	tNow.isdst = nil
	tNow = os.time(tNow)
		for line in text:gmatch("(.-)\n") do
--			print(line)
			count = count + 1
			local timestamp = line:sub(1,29)			

if not lsObjects[timestamp] then
--2016-10-21 15:40:00.231029955 pos;16.674076;-106.274133;0 str;0 dev;10228 sta;16;53;1225,1106,1387,1158,1068,1648,1364,1178,1653,677,695,1215,654,1181,1166,1539,635,1542,689,728,1180,1591,934,1002,976,1505,724,1339,1199,1565,713,1503,1176,1187,1482,1196,1177,1079,1189,1451,1076,1013,1093,706,1046,1203,1128,1270,1346,1228,1173,1168,1320
			local y, mon, d, h, min, s, frac, lat, lon, alt, str, dev, sta = line:match('(%d%d%d%d)-(%d%d)-(%d%d) (%d%d):(%d%d):(%d%d)%.(%d+) pos;([%+%-%.%d]+);([%+%-%.%d]+);([%+%-%.%d]+) str;([%+%-%.%d]+) dev;([%+%-%.%d]+) sta;(.+)')
			if not y then print(line)
			else
			
local sta1, sta2, list = sta:match('(%d+);(%d+);(.+)')	-- First 2 seem to be counts?
local ID = 'LS-'..getChar(h)..getChar(min)..getChar(s)
if lastID[ID] then
	lastID[ID] = lastID[ID] + 1
	ID = ID..getChar(lastID[ID])
else
	lastID[ID] = 0
end

newCount = newCount + 1

if tonumber(alt) == 0 then alt = nil end
local comment
if str ~= '0' then
	comment = 'str='..str..' sta='..tostring(sta1)..' '..tostring(sta2)
else comment = tostring(sta1)..'/'..tostring(sta2)
end
local packet = header..APRS:ObjectHHMMSS(ID, h, min, s,
									{lat=lat, lon=lon, alt=alt,
									symbol='\\J', comment=comment})
local o = {ID=ID, lat=lat, lon=lon, comment=comment, hour=h, minute=min, second=s,
			GS=APRS:GridSquare(lat,lon,4), LS=APRS:GridSquare(lat,lon,6),
			line=line, packet=packet, timestamp=timestamp,
			time=os.time{year=y,month=mon,day=d,hour=h,min=min,sec=s}}
lsObjects[timestamp] = o
lightnings[ID] = o
tStrikeDelta = tStrikeDelta + 1
if not gridSquares[o.GS] then
	gridSquares[o.GS] = {} print("Created GS:"..o.GS)
	tGSDelta = tGSDelta + 1
end
gridSquares[o.GS][timestamp] = o
gridSquares[o.GS].updated = tNow
--print(timestamp.." in GS:"..o.GS)

if not strikeSquares[o.LS] then
	strikeSquares[o.LS] = {} print("Created LS:"..o.LS)
	tLZDelta = tLZDelta + 1
end
strikeSquares[o.LS][timestamp] = o
strikeSquares[o.LS].updated = tNow
--print(timestamp.." in GS:"..o.GS)


--print(tostring(tNow-o.time)..":"..packet)
stationList.packetReceived(packet)	-- put it on our local map
--table.insert(pendingStrikes,packet)	-- No longer put individual strikes on the map!
			end
--else
--	print("Duplicate Object at "..timestamp)
--	print("Original: "..lsObjects[timestamp].line)
--	print("Duplicate "..line)
end
		end
		
		toast.new(tostring(newCount).." / "..tostring(count).." from "..source, 2000)
		return newCount, count
end

local formatsRaw = {"!http://data.blitzortung.org/Data_1/Protected/Strokes/%Y/%m/%d/%H/%M.log",
				"!http://data.blitzortung.org/Data_2/Protected/Strokes/%Y/%m/%d/%H/%M.log",
				"!http://data.blitzortung.org/Data_3/Protected/Strokes/%Y/%m/%d/%H/%M.log"}

M.formats = {}
for i,f in pairs(formatsRaw) do
	table.insert(M.formats,{format=f})
end

local function showLightning()
	if config.lastTemps then
		local text = M.lastPass or ""
		text = text..string.format("\r\nT:%d %d %d %d %d", tGSActive, tStrikeActive, tGSDelta, tStrikeDelta, tPackets)
		for x,f in ipairs(M.formats) do
			if f.last then
				text = text..string.format("\r\n%s %7d %s",
								f.lastTime and "GASP" or "....",
								f.got or 0, f.last:sub(-20))
			end
		end
		if temptext and (temptext.last ~= text) then
			--print(text)
			local x,y = temptext:getLoc()
			temptext:setString ( text );
			temptext:fitSize()
			temptext:setLoc(x,y)
			temptext.last = text
		end
	elseif not temptext.last or temptext.last ~= "" then
		temptext:setString ("")
		temptext.last = ""
	end
end

performWithDelay( 1000, showLightning, 0)

function M:getRecentStrokes()
-- http://data.blitzortung.org/Data_1/Protected/Strokes/2016/10/21/20/20.log

	if not self.nextFormat then
		self.nextFormat = 1
		self.delay = 10000
	else
		self.nextFormat = self.nextFormat+1
		if self.nextFormat > #self.formats then
			self.nextFormat = 1
			self.delay = math.floor(2*60*1000/#self.formats)
		end
	end
	local thisFormat = self.formats[self.nextFormat]
	local tNow = os.time()
	local t = math.floor(tNow/(10*60))*10*60
	local URL = os.date(thisFormat.format, t)
	local lsSentCount = 0

	local function gotStrokes( task, responseCode )
		if responseCode == 206 then
			local gotString = task:getString()
			print("lightning:Got "..#gotString.." bytes from "..URL)
			print("lightning:Range:"..tostring(task:getResponseHeader("Content-Range")).." vs "..tostring(thisFormat.got))
			thisFormat.got = thisFormat.got + #gotString;
			lsSentCount = self:parse(task:getString(), URL)
			save(lightnings, 'lightnings.xml','.')
		elseif responseCode == 200 then
			local gotString = task:getString()
			print("lightning:Got "..#gotString.." bytes from "..URL)
			print("lightning:Range:"..tostring(task:getResponseHeader("Content-Range")).." vs "..tostring(thisFormat.got))
			thisFormat.got = thisFormat.got + #gotString;
			lsSentCount = self:parse(task:getString(), URL)
			save(lightnings, 'lightnings.xml','.')
		elseif responseCode == 416 then
			print("lightning:416 received, nothing new from "..tostring(thisFormat.got).." in "..tostring(task:getResponseHeader("Content-Range")))
		else
			print ( "lightning:gotStrokes:Network error:"..responseCode.." from "..URL)
			toast.new("gotStrokes:Network error:"..responseCode.." from "..URL, 10000)
		end
		local lsActiveCount, lsKillCount, gsActiveCount, gsSentCount, gsKillCount, lzActiveCount, lzSentCount, lzKillCount
														= self:killOld(10*60)	-- Kill older than 10 minutes
		self.lastPass = string.format("Squares:%d Zones:%d Strikes:%d\r\nSZ:+%d-%d=%d LZ:+%d-%d=%d L:+%d-%d=%d",
							gsActiveCount, lzActiveCount, lsActiveCount,
							gsSentCount, gsKillCount, gsSentCount-gsKillCount,
							lzSentCount, lzKillCount, lzSentCount-lzKillCount,
							lsSentCount, lsKillCount, lsSentCount-lsKillCount)
		tGSActive, tLZActive, tStrikeActive = gsActiveCount, lzActiveCount, lsActiveCount

		performWithDelay(self.delay, function() self:getRecentStrokes() end)
	end

	if thisFormat.last ~= URL then
		if thisFormat.last and not thisFormat.lastTime then
			thisFormat.lastTime = true
			URL = thisFormat.last
			print("lightning:OneLastTime for "..tostring(URL))
			self.delay = 5000
			self.nextFormat = self.nextFormat - 1	-- Do me again!
		else
			if thisFormat.lastTime then
				self.delay = 5000
			end
			thisFormat.got = 0
			thisFormat.last = URL
			thisFormat.lastTime = nil
			print("lightning:Switching to "..tostring(URL))
		end
	end
	if (tNow-t) < 30 and not thisFormat.lastTime then
		local delay = 30-(tNow-t)
		print("lightning:Delaying "..URL.." "..tostring(delay).." seconds")
		--toast.new("lighting Delaying "..URL.." "..tostring(delay).." seconds", delay*1000)
		performWithDelay( delay*1000, function() self:getRecentStrokes() end)
	else
		print("lightning:Fetching "..URL.." from "..tostring(thisFormat.got))
		local task = MOAIHttpTask.new ()
		task:setVerb ( MOAIHttpTask.HTTP_GET )
		task:setUrl ( URL )
		task:setHeader("Range", "bytes="..tostring(thisFormat.got).."-")
		task:setTimeout ( 15 )
		task:setCallback ( gotStrokes )
	--[[		task:setUserAgent ( string.format('%s from %s %s',
													tostring(config.StationID),
													MOAIEnvironment.appDisplayName,
													tostring(config.About.Version)) )
	]]
		task:setVerbose ( true )
		task:performAsync ()
	end
end

performWithDelay( 5000, function() M:getRecentStrokes() end)

return M
