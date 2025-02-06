local debugging = false

module(..., package.seeall)

local toast = require("toast");
local colors = require("colors");
local stations = require('stationList')
local APRS = require("APRS")
local QSOs = require('QSOs')
local LatLon = require("latlon")
--local QSO = require('QSO')

print("APRSmap:Loading service")
service = require("service")

print("APRSmap:Loading osmTiles")
osmTiles = require("osmTiles")	-- This currently sets the Z order of the map
print("APRSmap:Loaded osmTiles="..tostring(osmTiles))

local myWidth, myHeight

local RenderPassCount, totalDrawCount, totalRenderCount, totalRenderTime = 0, 0, 0, 0
local lastRenderWhen = 0

if MOAIRenderMgr and type(MOAIRenderMgr.setCallback) == 'function' then	-- was setRenderCallback
	MOAIRenderMgr:setCallback(
				function(lastDrawCount, lastRenderCount, lastRenderTime)
					RenderPassCount = RenderPassCount + 1
					totalDrawCount = totalDrawCount + lastDrawCount
					totalRenderCount = totalRenderCount + lastRenderCount
					totalRenderTime = totalRenderTime + lastRenderTime
--local now = MOAISim.getDeviceTime()
--print("APRSmap:renderCallback["..RenderPassCount.."]:Draw:"..lastDrawCount.." Render:"..lastRenderCount.." in:"..math.floor(lastRenderTime*1000).."ms dt:"..math.floor((now-lastRenderWhen)*1000))
--lastRenderWhen = now
				end)
end

local memoryText, messageButton
local lastFrameCount = 0
if type(MOAISim.getElapsedFrames) == 'function' then
	lastFrameCount = MOAISim.getElapsedFrames()
elseif type(MOAIRenderMgr.getRenderCount	) == 'function' then
	lastFrameCount = MOAIRenderMgr.getRenderCount()
elseif type(MOAISim.getStepCount) == 'function' then
	lastFrameCount = MOAISim.getStepCount()
end
local lastMemoryTime = MOAISim.getDeviceTime()
local entryCount = 0

local hasProcStatm

local function getVirtualResident()
	if hasProcStatm == nil or hasProcStatm then
		local hFile, err = io.open("/proc/self/statm","r")
		if hFile and not err then
			local xmlText=hFile:read("*a"); -- read file content
			io.close(hFile);
			local s, e, virtual, resident = string.find(xmlText, "(%d+)%s(%d+)")
			if virtual and resident then
				hasProcStatm = true
				return tonumber(virtual)*4096, tonumber(resident)*4096
			else
				hasProcStam = false
			end
		else
			hasProcStatm = false
			print( err )
		end
	end
	return nil
end

local memoryLast = 0
local lastPerf = nil
local lastMemoryUsage = MOAISim.getDeviceTime()
--local nextMemoryLog = 0

local function updateMemoryUsage()
	local newCount = 0
	if type(MOAISim.getElapsedFrames) == 'function' then
		newCount = MOAISim.getElapsedFrames()
	elseif type(MOAIRenderMgr.getRenderCount	) == 'function' then
		newCount = MOAIRenderMgr.getRenderCount()
	elseif type(MOAISim.getStepCount) == 'function' then
		newCount = MOAISim.getStepCount()
	end
	local localCount = newCount - lastFrameCount
	lastFrameCount = newCount
	local now = MOAISim.getDeviceTime()
	local elapsed = now-lastMemoryTime
	local fps = 0
	if elapsed > 0 then
		fps = localCount / (now-lastMemoryTime)
	end
	lastMemoryTime = now
	local memuse = MOAISim:getMemoryUsage()
	if not (type(memuse._sys_vs) == 'number' and type(memuse._sys_rss) == 'number') then
		memuse._sys_vs, memuse._sys_rss = getVirtualResident()
	end

	local avgDraws, avgRenders, avgRenderTime, renderPercent = 0,0,0,0
	
	if MOAIRenderMgr
	and type(MOAIRenderMgr.setCallback) ~= 'function' then
--[[
	@lua	getPerformance
	@text	Returns an estimated frames per second and other performance counters 
			based on measurements taken at every render.

	@out	number fps		1 Estimated frames per second.
	@out	number seconds	2 Last ActionTree update duration
	@out	number seconds  3 Last NodeMgr update duration
	@out	number seconds  4 Last sim duration
	@out	number seconds  5 Last render duration
	@out	number count    6 Total render count
	@out	number seconds  7 Total render duration
]]
		if type(MOAISim.getPerformance) == 'function' then
			local newPerf = {MOAISim.getPerformance()}
			if not lastPerf then lastPerf = newPerf end
--[[
			local text = ''
			if #newPerf >= 5 then
				text = text..string.format("getPerformance:fps:%d msec(Action:%.2f Node:%.2f Sim:%.2f Render:%.2f)",
											newPerf[1], newPerf[2]*1000, newPerf[3]*1000, newPerf[4]*1000, newPerf[5]*1000)
				if #newPerf >= 7 then
					local deltaRender = newPerf[6]-lastPerf[6]
					local deltaRenderTime = (newPerf[7]-lastPerf[7])*1000
					if deltaRender > 0 then
						text = text..string.format(" Renders:%d*%.2f=%.2f",
												deltaRender, deltaRenderTime/deltaRender, deltaRenderTime)
					end
				end
			end
			if text ~= '' then print(text) end
]]
			if #newPerf == 7 then
				RenderPassCount = newPerf[6]-lastPerf[6]
				totalRenderCount = newPerf[6]-lastPerf[6]
				totalRenderTime = newPerf[7]-lastPerf[7]
			elseif #newPerf == 5 then
				avgRenders = 1
				avgRenderTime = newPerf[5]
			end
			lastPerf = newPerf
		end

--[[
		if type(MOAIRenderMgr.getPerformanceDrawCount) == 'function' then
			totalDrawCount = MOAIRenderMgr.getPerformanceDrawCount()
			if totalDrawCount > 0 then
				print("getPerformanceDrawCount returned "..tostring(totalDrawCount))
			end
		end
]]
	end
	if RenderPassCount > 0 then
		avgDraws = totalDrawCount / RenderPassCount
		avgRenders = totalRenderCount / RenderPassCount
		avgRenderTime = totalRenderTime / RenderPassCount
	end
	if elapsed > 0 then
		renderPercent = totalRenderTime / elapsed * 100
	end
	local memoryNow = memuse.lua or 0
	local memoryDelta = (memoryNow - memoryLast) / 1024
	memoryLast = memoryNow
	local mbMult = 1/1024/1024
	local text
	if Application.viewWidth > Application.viewHeight then	-- wider screens get more info
		text = string.format('%.1f+%.1f=%.1fMB%s fps:%.1f/%.1f/%i %i(%i)@%.1fms=%.1f%%',
								memuse.lua*mbMult,
								memuse.texture*mbMult,
								memuse.total*mbMult,
	((type(memuse._sys_vs) == 'number' and type(memuse._sys_rss) == 'number')
		and ("("..math.floor(memuse._sys_rss*mbMult).."/"..math.floor(memuse._sys_vs*mbMult).."MB)")
		or ""),
								fps, MOAISim.getPerformance(), RenderPassCount,
								avgRenders, avgDraws, avgRenderTime*1000, renderPercent)
		text = text..string.format(" Delta:%.2fKB", memoryDelta)
	else text = string.format('%.0f+%.0f=%.0fMB%s %ifps %i(%i)=%.0f%%',
								memuse.lua*mbMult,
								memuse.texture*mbMult,
								memuse.total*mbMult,
	((type(memuse._sys_vs) == 'number' and type(memuse._sys_rss) == 'number')
		and ("("..math.floor(memuse._sys_rss*mbMult).."/"..math.floor(memuse._sys_vs*mbMult).."MB)")
		or ""),
								RenderPassCount,
								avgRenders, avgDraws, renderPercent)
	end
	RenderPassCount, totalDrawCount, totalRenderCount, totalRenderTime = 0, 0, 0, 0
	_G["vmText"] = text
	
--	if os.time() > nextMemoryLog then
--		nextMemoryLog = os.time() + 5	-- Every 5 seconds
--		print(text)
--	end
	
	local now = MOAISim.getDeviceTime()
	local delta = (now-lastMemoryUsage)
	--print(string.format("Delta:%.2fmsec %s", delta*1000, text))
	lastMemoryUsage = now

	if memoryText then
		--if debugging then print(os.date("%H:%M:%S ")..text)
--		if debugging or (Application and type(Application.isDesktop) == 'function' and Application:isDesktop()) then
--			print(text)
--		end
		memoryText:setString(text)
--		memoryText:fitSize()
--		memoryText:setLoc(Application.viewWidth/2, 55*config.Screen.scale)
		--memoryText:fitSize(#text)
	else print(text)
	end
end
performWithDelay2("updateMemoryUsage", 1000, updateMemoryUsage, 0)

local function positionMessageButton(width, height)
    if messageButton then messageButton:setRight(width-10) messageButton:setTop(50*config.Screen.scale) end
end

local function runQSOsButton(layer, myWidth, myHeight)
	local function checkQSOsButton()
		local current = SceneManager:getCurrentScene()
		local new = QSOs:getMessageCount()	-- Get all new message count
		if current.name == 'APRSmap' then	-- Only if I'm current
			if new > 0 then
				if not messageButton then
					local alpha = 0.75
					messageButton = Button {
						text = "QSOs",
						red=0*alpha, green=240/255*alpha, blue=0*alpha, alpha=alpha,
						size = {100, 66},
						layer=layer, priority=2100000000,
						onClick = function()
										SceneManager:openScene("QSOs_scene", {animation = "popIn", backAnimation = "popOut", })
									end,
					}
					messageButton:setScl(config.Screen.scale,config.Screen.scale,1)
					positionMessageButton(Application.viewWidth, Application.viewHeight)
					--messageButton:setRight(myWidth-10) messageButton:setTop(50*config.Screen.scale)
				end
			elseif messageButton then
				--layer:getPartition():removeProp(messageButton)
				messageButton:dispose()
				messageButton = nil
			end
			performWithDelay2("checkQSOs",5000,checkQSOsButton)
		elseif messageButton then
			--layer:getPartition():removeProp(messageButton)
			messageButton:dispose()
			messageButton = nil
		end
	end
	performWithDelay(1000,checkQSOsButton)
end

local function resizeHandler ( width, height )
	myWidth, myHeight = width, height
	print('APRSmap:onResize:'..tostring(width)..'x'..tostring(height))
	APRSmap.backLayer:setSize(width,height)
	--if recentImage then recentImage:setSize(myWidth-40, myHeight-40) end
	if service then service:mapResized(width,height) end
	tileLayer:setSize(width,height)
	layer:setSize(width,height)
	positionMessageButton(width, height)
	if stilltext then
		stilltext:setLoc(stilltext:getWidth()/2+config.Screen.scale, height-stilltext:getHeight()/2)		--0*config.Screen.scale)
	end
	whytext:setLoc ( width/2, height-32*config.Screen.scale )
	gpstext:setLoc ( width/2, height-65*config.Screen.scale )
	speedtext:setRight(width) speedtext:setTop(125*config.Screen.scale)
	odotext:setRight(width) odotext:setTop(speedtext:getBottom())

--	if titleBackground then
--		titleGroup:removeChild(titleBackground)
--		titleBackground:dispose()
--	end
	titleBackground:setSize(width,40*config.Screen.scale)
--	titleBackground = Graphics {width = width, height = 40*config.Screen.scale, left = 0, top = 0}
--    titleBackground:setPenColor(0.25, 0.25, 0.25, 0.75):fillRect()	-- dark gray like Android
--	titleBackground:setPriority(2000000000)
--	titleGroup:addChild(titleBackground)
	local x,y = titleText:getSize()
	titleText:setLoc(width/2, 25*config.Screen.scale)

	local yMarch, yMargin = 55, 4*config.Screen.scale
	print(string.format("memoryText@%d, was 55, height %d", yMarch, memoryText:getHeight()))
	memoryText:setLoc ( width/2, yMarch*config.Screen.scale)
	yMarch = memoryText:getBottom() + yMargin
	print(string.format("lwdtext@%d, was 80, height %d", yMarch, lwdtext:getHeight()))
	lwdtext:setLoc ( width/2, yMarch*config.Screen.scale )	-- was 80
	lwdtext:setTop(yMarch)
	yMarch = lwdtext:getBottom() + yMargin
	if kisstext then
		print(string.format("kistext@%d, was 105, height %d", yMarch, kisstext:getHeight()))
		kisstext:setLoc ( width/2, yMarch*config.Screen.scale )	-- was 105
		kisstext:setTop(yMarch)
		yMarch = kisstext:getBottom() + yMargin
	end
	if IPFStext then
		print(string.format("IPFStext@%d, was 130, height %d", yMarch, IPFStext:getHeight()))
		local h = IPFStext:getHeight()
		IPFStext:setLoc( width/2, yMarch*config.Screen.scale+h/2 )	-- was 130
		IPFStext:setTop(yMarch)
		yMarch = IPFStext:getBottom() + yMargin
	end
	if temptext then
		local h = temptext:getHeight()
		local top = height/2 - h/2
		if top > yMarch then
			print(string.format("temptext height %d top %d yMarch %d, center at %d", h, top, yMarch, height/2))
			temptext:setLoc ( width/2, height/2 )
		else
			print(string.format("temptext height %d top %d yMarch %d, set to %d", h, top, yMarch, yMarch*config.Screen.scale+h/2))
			temptext:setLoc ( width/2, yMarch*config.Screen.scale+h/2 )
			temptext:setTop(yMarch)
		end
		yMarch = temptext:getBottom() + yMargin
	end
	if recentImage then
		local x,y = osmTiles:whereIS(recentImage.lat, recentImage.lon)
		if x and y then
			x,y = osmTiles:translateXY(x,y)
			print("recentImage:resize:Moving to "..tostring(x)..","..tostring(y))
			recentImage:setLoc ( x,y )
			--recentImage:setLoc ( width/2, height/2 )
		end
	end
	if typeImage then
		typeImage:setLoc(width-140, height/2-38)
	end
	if coordImage then
		coordImage:setLoc(width-200, height/2+26)
	end
	if pxytext then pxytext:setLoc ( width/2, 95*config.Screen.scale ) end

	if osmTiles then osmTiles:setSize(width, height) end
end

local function dumpTable(k,v)
	print(tostring(k)..':'..tostring(v))
	if type(v) == 'table' then
		for k1,v1 in pairs(v) do
			dumpTable(k..'.'..k1, v1)
		end
	end
end

local function addTrkPts(points, trkpt)
	if not points then points = {} end
	for i, v in ipairs(trkpt) do
		if v.lat and v.lon then
			points[#points+1] = tonumber(v.lat)
			points[#points+1] = tonumber(v.lon)
			--print("trkpt["..tostring(i).."] @ "..tostring(v.lat).." "..tostring(v.lon).." ele:"..tostring(v.ele))
		else print(printableTable("trkpt["..tostring(i).."]", v))
		end
	end
	return points
end

local function dumptrack(trkseg)
	if type(trkseg) == 'table' and type(trkseg.trkpt) == 'table' then
		print('New Track with '..tostring(#trkseg.trkpt)..' points:')
		if #trkseg.trkpt > 0 then	-- More than one trkpt
			return addTrkPts(nil, trkseg.trkpt)
		else
			print("Single trkpt in ", printableTable("trkseg.trkpt",trkseg.trkpt))
		end
	else
		print("trkseg:"..tostring(trkseg))
		if type(trkseg) == 'table' then
			print(printableTable("trkseg",trkseg))
			local total
			for i, t in ipairs(trkseg) do
				if type(t) == 'table' and type(t.trkpt) == 'table' then
					total = addTrkPts(total, t.trkpt)
				else
					print("trkseg["..tostring(i).."]=>"..type(t))
				end
			end
			return total
		end
	end
end

local function addOdometer(poly)
	if #poly >- 4 then
		poly.odometer = 0
		local atPoint = LatLon.new(poly[1], poly[2])
		for i=3,#poly,2 do
			local toPoint = LatLon.new(poly[i], poly[i+1])
			local dist = kmToMiles(atPoint.distanceTo(toPoint))
			poly.odometer = poly.odometer + dist
			atPoint = toPoint
		end
	end
end
	
local function processTrkseg(polies, trkpnts, color, width, alpha, name)
	if type(trkpnts) == 'table' and type(trkpnts.trkpt) == 'table' then
		print('New Track with '..tostring(#trkpnts.trkpt)..' points:')
		if #trkpnts.trkpt > 0 then	-- More than one trkpt
			local poly = addTrkPts(nil, trkpnts.trkpt)
			if poly then
				poly.name = name
				if color then poly.color = colors:getColorArray(color) else poly.color = colors:getRandomTrackColorArray() end
				--poly.color = colors:getRandomTrackColorArray()
				if width then poly.lineWidth = width else poly.lineWidth = 4 end
				if alpha then poly.alpha = alpha end
				addOdometer(poly)
				poly.showArrows = true
				osmTiles:showPolygon(poly,name)
				if not polies then
					polies = {odometer=0}
				end
				polies[#polies+1] = poly
				polies.odometer = polies.odometer + poly.odometer
			end
		else
			print("processTrkpnts:Single trkpt in ", printableTable("trkpnts.trkpt",trkpnts.trkpt))
		end
	else
		print("processTrkpnts:Missing trkpts in ", printableTable("trkpnts",trkpnts))
	end
	return polies
end
	
local function processTrksegs(polies, trksegs, color, width, alpha, name)
	if type(trksegs) == 'table' and type(trksegs.trkpt) == 'table' then
		polies = processTrkseg(polies, trksegs, color, width, alpha, name)
	else
		for i, t in ipairs(trksegs) do
			polies = processTrkseg(polies, t, color, width, alpha, name.."["..tostring(i).."]")
		end
	end
	return polies
end
	
local function processTrk(polies, trk, color, width, alpha, name)
	polies = processTrksegs(polies, trk.trkseg, color, width, alpha, name)
	return polies
end

local function addRtePts(points, rtept)
	if not points then points = {} end
	for i, v in ipairs(rtept) do
		if v.lat and v.lon then
			points[#points+1] = tonumber(v.lat)
			points[#points+1] = tonumber(v.lon)
			--print("rtept["..tostring(i).."] @ "..tostring(v.lat).." "..tostring(v.lon).." ele:"..tostring(v.ele))
		else print(printableTable("rtept["..tostring(i).."]", v))
		end
	end
	return points
end

	
local function processRtept(polies, rte, color, width, alpha, name)
	if type(rte) == 'table' and type(rte.rtept) == 'table' then
		print('New Route with '..tostring(#rte.rtept)..' points:')
		if #rte.rtept > 0 then	-- More than one rtept
			local poly = addRtePts(nil, rte.rtept)
			if poly then
				poly.name = name
				if color then poly.color = colors:getColorArray(color) else poly.color = colors:getRandomTrackColorArray() end
				--poly.color = colors:getRandomTrackColorArray()
				if width then poly.lineWidth = width else poly.lineWidth = 4 end
				if alpha then poly.alpha = alpha end
				addOdometer(poly)
				poly.showArrows = true
				osmTiles:showPolygon(poly,name)
				if not polies then
					polies = {odometer=0}
				end
				polies[#polies+1] = poly
				polies.odometer = polies.odometer + poly.odometer
			end
		else
			print("processRtept:Single rtept in ", printableTable("rte.rtept",rte.rtept))
		end
	else
		print("processRtept:Missing rtept in ", printableTable("rte",rte))
	end
	return polies
end
	
local function processRte(polies, rte, color, width, alpha, name)
	if type(rte) == 'table' and type(rte.rtept) == 'table' then
		polies = processRtept(polies, rte, color, width, alpha, name)
	end
	return polies
end
	
local function dumptracks(gpx, color, width, alpha, name)
	name = name or "GPX"
	local polies = nil
	if type(gpx) == 'table' and type(gpx.trk) == 'table' then
		print(printableTable("gpx.trk",gpx.trk))
		print(name.." Has "..tostring(#gpx.trk).." Track(s)")
		if #gpx.trk > 0 then	-- More than one trk
			for i, v in ipairs(gpx.trk) do
				polies = processTrk(polies, v, color, width, alpha, name)
			end
		elseif type(gpx.trk.trkseg) == 'table' then
			polies = processTrk(polies, gpx.trk, color, width, alpha, name)
		end
	end
	if type(gpx) == 'table' and type(gpx.rte) == 'table' then
		print(printableTable("gpx.rte",gpx.rte))
		print(name.." Has "..tostring(#gpx.rte).." Route(s)")
		if #gpx.rte > 0 then	-- More than one rte
			for i, v in ipairs(gpx.rte) do
				print(name.." route["..tostring(i).."] name:"..tostring(v.name))
				polies = processRte(polies, v, color, width, alpha, name)
			end
		elseif type(gpx.rte.rtept) == 'table' then
			polies = processRte(polies, gpx.rte, color, width, alpha, name)
		end
	end
	return polies
end

local function showGPX(gpxFile, color, width, alpha)
	local xmlapi = require( "xml" ).newParser()
	local gpx = xmlapi:loadFile( gpxFile, "." )
	print("loadFile("..tostring(gpxFile).." returned "..tostring(gpx))
	if not gpx then return gpx end
	simplified = xmlapi:simplify( gpx )
	--print(printableTable(gpxFile, simplified))
	--dumpTable(gpxFile, simplified)
	local polies = dumptracks(simplified, color, math.floor(config.Screen.scale*width+0.5), alpha, gpxFile)
	if polies then
		polies.name = gpxFile
		polies.color = color
		polies.lineWidth = width
	end
	return polies
end

local function getGPXs()
	return gpxFiles
end

local function countGPX()
	return #gpxFiles
end

local function isGPXVisible()
	return gpxVisible
end

local function showGPXs()
	if not gpxVisible then
		for i,polies in pairs(gpxFiles) do
			for j, p in ipairs(polies) do
				osmTiles:showPolygon(p,p.stationID)
			end
		end
		gpxVisible = true
	end
end

local function hideGPXs()
	if gpxVisible then
		for i,polies in pairs(gpxFiles) do
			for j, p in ipairs(polies) do
				osmTiles:removePolygon(p)
			end
		end
		gpxVisible = false
	end
end

function onStart()
    print("APRSmap:onStart()")

	--local iniLat, iniLon, iniZoom = 27.996683, -80.659083, 12
	local iniLat, iniLon, iniZoom = 27.996683, -80.659083, 12
	if tonumber(config.lastMapLat) then iniLat = tonumber(config.lastMapLat) end
	if tonumber(config.lastMapLon) then iniLon = tonumber(config.lastMapLon) end
	if tonumber(config.lastMapZoom) then iniZoom = tonumber(config.lastMapZoom) end
	print("APRSmap:Starting osmTiles")
	osmTiles:start()
	print('APRSmap:moveTo:'..iniLat..' '..iniLon..' zoom:'..iniZoom)
	if debugging then
		osmTiles:moveTo(iniLat, iniLon, iniZoom)
	else
		local s, text = pcall(osmTiles.moveTo, osmTiles, iniLat, iniLon, iniZoom)
		if not s then print("APRSmap:onStart:moveTo Failed with "..tostring(text)) end
	end

	local iniScale = 1
	if tonumber(config.lastMapScale) then iniScale = tonumber(config.lastMapScale) end
	print('APRSmap:setTileScale:'..iniScale)
	osmTiles:setTileScale(iniScale)

	local iniAlpha = 1.0	-- Start 100% opaque
	if tonumber(config.lastMapAlpha) then iniAlpha = tonumber(config.lastMapAlpha) end
	print('APRSmap:setTileAlpha:'..iniAlpha)
	osmTiles:setTileAlpha(iniAlpha)

	osmTiles:showLabels(not config.lastLabels)	-- lastLabels flags suppression

	print("APRSmap:setupME w/osmTiles")
	stations:setupME(osmTiles)	-- Have to tell the station list about the map module

	print("APRSmap:starting service and APRSIS w/config")
	service:start(config)
	if (config.APRSIS.Enabled) then
		APRSIS:start()
	end
	
	--showGPX("TripleN.gpx")
	--showGPX("R4R_100_309nodes.gpx", "crimson", 9)
	--showGPX("R4R_60_226nodes.gpx", "darkgreen", 7)
	--showGPX("R4R_30_106nodes.gpx", "red", 5)
	--showGPX("R4R_10_64nodes.gpx", "darkcyan", 3)
	--showGPX("CTC2015-100.gpx", "darkgreen", 9)
	--showGPX("CTC2015-062.gpx", "red", 5)
	--showGPX("HH100-2015_406nodes.gpx", "crimson", 9)
	--showGPX("HH70-2015_306nodes.gpx", "darkgreen", 6)
	--showGPX("HH35-2015_304nodes.gpx", "red", 3)
	--showGPX("R4R_10_64nodes.gpx", "crimson", 9)
	gpxFiles = {}
	gpxVisible = true
--	gpxFiles[#gpxFiles+1] = showGPX("2016_TDC_101_360nodes.gpx", "crimson", 9)
--	gpxFiles[#gpxFiles+1] = showGPX("2016_TDC_63_202nodes.gpx", "darkgreen", 7)
--	gpxFiles[#gpxFiles+1] = showGPX("2016_TDC_50_170nodes.gpx", "red", 5)
--	gpxFiles[#gpxFiles+1] = showGPX("2016_TDC_25_170nodes.gpx", "darkcyan", 3)

--	gpxFiles[#gpxFiles+1] = showGPX("2017TDC_101_mi_386nodes.gpx", "crimson", 9)
--	gpxFiles[#gpxFiles+1] = showGPX("2017TDC_63_mi_278nodes.gpx", "darkgreen", 7)
--	gpxFiles[#gpxFiles+1] = showGPX("2017TDC_50_mi_250nodes.gpx", "red", 5)
--	gpxFiles[#gpxFiles+1] = showGPX("2017TDC_25_mi_200nodes.gpx", "darkcyan", 3)

	--gpxFiles[#gpxFiles+1] = showGPX("2016_R4R_100_MilesA_316nodes.gpx", "crimson", 9)
	--gpxFiles[#gpxFiles+1] = showGPX("2016_R4R_60_MilesA_170nodes.gpx", "darkgreen", 7)
	--gpxFiles[#gpxFiles+1] = showGPX("2016_R4R_30_MilesA_130nodes.gpx", "red", 5)
	--gpxFiles[#gpxFiles+1] = showGPX("2016_R4R_10_MilesA_64nodes.gpx", "darkcyan", 3)

	performWithDelay(1000, function()

--		table.insert(gpxFiles,showGPX("TSE-2017-August-21-Umbral-Path.gpx", "crimson", 9, 0.6))
	
--		table.insert(gpxFiles,showGPX("2017_-_101_mi_TDC_462nodes.gpx", "crimson", 9, 0.6))
--		table.insert(gpxFiles,showGPX("2017_-_63_mi_TDC_340nodes.gpx", "darkgreen", 7, 0.5))
--		table.insert(gpxFiles,showGPX("2017_-_50_mi_TDC_330nodes.gpx", "red", 5, 0.4))
--		table.insert(gpxFiles,showGPX("2017_-_25_mi_TDC_354nodes.gpx", "darkblue", 3, 0.3))
--		table.insert(gpxFiles,showGPX("2017_-_10_mi_TDC_190nodes.gpx", "purple", 1, 0.2))

--		table.insert(gpxFiles,showGPX("5-SWFL_TdC-100_Mile_Route-Red+_266nodes.gpx", "red", 9, 0.6))
--		table.insert(gpxFiles,showGPX("4-SWFL_TdC-62_Mile_Route-Orange+_242nodes.gpx", "orange", 7, 0.5))
--		table.insert(gpxFiles,showGPX("3-SWFL_TdC-35_Mile_Route-Green+_196nodes.gpx", "green", 5, 0.4))
--		table.insert(gpxFiles,showGPX("2-SWFL_TdC-20_Mile_Route-Purple+_140nodes.gpx", "purple", 3, 0.3))
--		table.insert(gpxFiles,showGPX("1-SWFL_TdC-10_Mile_Route-Blue+_96nodes.gpx", "blue", 1, 0.2))

--		table.insert(gpxFiles,showGPX("2016MSC_102_400nodes.gpx", "crimson", 9, 0.6))
--		table.insert(gpxFiles,showGPX("2016MSC_77_252nodes.gpx", "darkgreen", 7, 0.5))
--		table.insert(gpxFiles,showGPX("2016MSC_50_206nodes.gpx", "red", 5, 0.4))
--		table.insert(gpxFiles,showGPX("2016MSC_21_83nodes.gpx", "darkblue", 3, 0.3))

		local function addGPX(polies)
			if polies then table.insert(gpxFiles,polies) end
		end

--		addGPX(showGPX("2018TDC/2018_-_101_mi_Tour_de_Cure.gpx", "crimson", 9, 0.6))
--		addGPX(showGPX("2018TDC/2018_-_63_mi_Tour_de_Cure.gpx", "crimson", 7, 0.6))
--		addGPX(showGPX("2018TDC/2018_-_50_mi_Tour_de_Cure.gpx", "darkgreen", 5, 0.5))
--		addGPX(showGPX("2018TDC/2018_-_25_mi_Tour_de_Cure.gpx", "red", 3, 0.4))
--		addGPX(showGPX("2018TDC/2018_-_10_mi_Tour_de_Cure.gpx", "darkblue", 1, 0.3))

		print("loading GPXs")

--		addGPX(showGPX("2018TDC/2018_-_101_mi_Tour_de_Cure.gpx", "crimson", 9, 0.6))
--		addGPX(showGPX("2018R4R/2018_Ride-For-RMHCCF_60_Mile_Route_-_Actual_63.gpx", "crimson", 7, 0.6))
--		addGPX(showGPX("2018R4R/2018_Ride-For-RMHCCF_30_Mile_Route_-_Actual_33.gpx", "darkgreen", 5, 0.5))
--		addGPX(showGPX("2018R4R/2018_Ride-For-RMHCCF_10_Mile_Route_-_Actual_10.1.gpx", "red", 3, 0.4))
--		addGPX(showGPX("2018R4R/2018_Ride-For-RMHCCF_3.5_Mile_Fun_Ride_-_Actual_3.5.gpx", "darkblue", 1, 0.3))

--		addGPX(showGPX("2018R4R/2018_RMHCCF_63_252nodes.gpx", "crimson", 7, 0.6))
--		addGPX(showGPX("2018R4R/2018_RMHCCF_33_120nodes.gpx", "darkgreen", 5, 0.5))
--		addGPX(showGPX("2018R4R/2018_RMHCCF_10_85nodes.gpx", "red", 3, 0.4))
--		addGPX(showGPX("2018R4R/2018_RMHCCF_3_5_6nodes.gpx", "darkblue", 1, 0.3))
		
--[[	2019_TdC_-_101_Mi.gpx
		2019_TdC_-_10_Mi.gpx
		2019_TdC_-_25_Mi.gpx
		2019_TdC_-_50_Mi.gpx
		2019_TdC_-_5K_Run_Walk.gpx
		2019_TdC_-_68_Mi.gpx --]]
--		addGPX(showGPX("2019TDC/2019_TdC_-_101_Mi.gpx", "crimson", 9, 0.6))
--		addGPX(showGPX("2019TDC/2019_TdC_-_68_Mi.gpx", "crimson", 7, 0.6))
--		addGPX(showGPX("2019TDC/2019_TdC_-_50_Mi.gpx", "darkgreen", 5, 0.5))
--		addGPX(showGPX("2019TDC/2019_TdC_-_25_Mi.gpx", "red", 3, 0.4))
--		addGPX(showGPX("2019TDC/2019_TdC_-_10_Mi.gpx", "darkblue", 1, 0.3))
--		addGPX(showGPX("2019TDC/2019_TdC_-_5K_Run_Walk.gpx", "lightblue", 1, 0.3))

--		addGPX(showGPX("2019TDC/2019_TdC_-_101_Mi_342nodes.gpx", "yellow", 24, 0.6))
--		addGPX(showGPX("2019TDC/2019_TdC_-_68_Mi_264nodes.gpx", "orange", 20, 0.6))
--		addGPX(showGPX("2019TDC/2019_TdC_-_50_Mi_282nodes.gpx", "green", 16, 0.5))
--		addGPX(showGPX("2019TDC/2019_TdC_-_25_Mi_204nodes.gpx", "blue", 12, 0.4))
--		addGPX(showGPX("2019TDC/2019_TdC_-_10_Mi_138nodes.gpx", "purple", 8, 0.3))
--		addGPX(showGPX("2019TDC/2019_TdC_-_5K_Run_Walk_34nodes.gpx", "deeppink", 4, 0.3))
		
--		addGPX(showGPX("2019Glimcher/DoubleTrksegs.gpx", "yellow", 24, 0.6))
--		addGPX(showGPX("2019Glimcher/SingleTrk2Segs.gpx", "yellow", 24, 0.6))
--		addGPX(showGPX("2019Glimcher/SingleTrkSingleSeg.gpx", "yellow", 24, 0.6))
--		addGPX(showGPX("2019Glimcher/Day1RouteGPX.gpx", "orange", 24, 0.6))
--		addGPX(showGPX("2019Glimcher/Day2RouteGPX.gpx", "yellow", 18, 0.6))
--		addGPX(showGPX("2019Glimcher/Day1AlternateRouteLowerTrailGPX.gpx", "orange", 16, 0.5))
--		addGPX(showGPX("2019Glimcher/Day1RouteGPX.gpx", "orange", 7, 0.6))
--		addGPX(showGPX("2019Glimcher/Day2RouteGPX.gpx", "yellow", 5, 0.6))
--		addGPX(showGPX("2019Glimcher/Day1AlternateRouteLowerTrailGPX.gpx", "orange", 3, 0.5))
--		addGPX(showGPX("2019Glimcher/Day1Busted1.gpx", "orange", 7, 0.6))
--		addGPX(showGPX("2019Glimcher/Day1Busted2.gpx", "yellow", 7, 0.6))
		
--		addGPX(showGPX("TripleN.gpx", "lime", 36, 0.3))


--[[
		addGPX(showGPX("2019mtdora/Fri-100BakeryCentury_-_NEW.gpx", "yellow", 24, 0.6))
		addGPX(showGPX("2019mtdora/Fri-64BakeryMetricVer3.gpx", "orange", 20, 0.6))
		addGPX(showGPX("2019mtdora/Fri-37LegStretch(1).gpx", "green", 16, 0.5))
		addGPX(showGPX("2019mtdora/Fri-25LakeDoraLoop.gpx", "blue", 12, 0.4))
--		addGPX(showGPX("2019mtdora/2019_TdC_-_10_Mi_138nodes.gpx", "purple", 8, 0.3))
--		addGPX(showGPX("2019mtdora/2019_TdC_-_5K_Run_Walk_34nodes.gpx", "deeppink", 4, 0.3))
]]

--[[
		addGPX(showGPX("2019mtdora/Sat-100_Swamp_Century.gpx", "yellow", 24, 0.6))
		addGPX(showGPX("2019mtdora/Sat-63SwampMetric.gpx", "orange", 20, 0.6))
		addGPX(showGPX("2019mtdora/Sat-41ThreeBobs.gpx", "green", 16, 0.5))
		addGPX(showGPX("2019mtdora/Sat-29ThrillHill.gpx", "blue", 12, 0.4))
		addGPX(showGPX("2019mtdora/Sat-18GracieGrowsUp.gpx", "purple", 8, 0.3))
--		addGPX(showGPX("2019mtdora/2019_TdC_-_5K_Run_Walk_34nodes.gpx", "deeppink", 4, 0.3))
]]

--[[
		addGPX(showGPX("2019mtdora/Sun-55BattleBuckhill.gpx", "yellow", 24, 0.6))
		addGPX(showGPX("2019mtdora/Sun-40AssaultSugarloaf.gpx", "orange", 20, 0.6))
		addGPX(showGPX("2019mtdora/Sun-30RollNRecover.gpx", "green", 16, 0.5))
		addGPX(showGPX("2019mtdora/Sun-19PhotoScavenger.gpx", "blue", 12, 0.4))
		addGPX(showGPX("2019mtdora/2019_TdC_-_10_Mi_138nodes.gpx", "purple", 8, 0.3))
		addGPX(showGPX("2019mtdora/2019_TdC_-_5K_Run_Walk_34nodes.gpx", "deeppink", 4, 0.3))
]]


--		addGPX(showGPX("2019R4R/2019R4R-61.0_168nodes.gpx", "yellow", 24, 0.6))
--[[
		addGPX(showGPX("2019R4R/2019R4R-61.0_168nodes.gpx", "orange", 20, 0.6))
		addGPX(showGPX("2019R4R/2019R4R-30.5_130nodes.gpx", "green", 16, 0.5))
		addGPX(showGPX("2019R4R/2018R4R-10.1_62nodes.gpx", "blue", 12, 0.4))
		addGPX(showGPX("2019R4R/2019R4R-05K_28nodes.gpx", "purple", 8, 0.3))
		addGPX(showGPX("2019R4R/2018R4R-03.5_38nodes.gpx", "deeppink", 4, 0.3))
]]
--[[
		addGPX(showGPX("2020TDC/2020_TdC_-101_Mi_254nodes.gpx", "orange", 20, 0.6))
		addGPX(showGPX("2020TDC/2020_TdC_-_63_Mi_190nodes.gpx", "green", 16, 0.5))
		addGPX(showGPX("2020TDC/2020_TdC_-_50_Mi_178nodes.gpx", "blue", 12, 0.4))
		addGPX(showGPX("2020TDC/2020_TdC_-_25_Mi_174nodes.gpx", "purple", 8, 0.3))
		addGPX(showGPX("2020TDC/2020_TdC_-_10_Mi_108nodes.gpx", "deeppink", 4, 0.3))
		addGPX(showGPX("2020TDC/2020_TdC_-_5k_Walk_Run_38nodes.gpx", "pink", 4, 0.3))
]]
--[[
		addGPX(showGPX("2021R4R/2021_RMHCCF_60_Mile_Actual_61_418nodes.gpx", "green", 16, 0.5))
		addGPX(showGPX("2021R4R/2021_RMHCCF_30_Mile_Actual_30.5_120nodes.gpx", "blue", 12, 0.4))
		addGPX(showGPX("2021R4R/2021_RMHCCF_10_Mile_Actual_10.1_109nodes.gpx", "purple", 8, 0.3))
		addGPX(showGPX("2021R4R/2021_RMHCCF_3.5_Mile_Actual_3.5_46nodes.gpx", "deeppink", 4, 0.3))
		addGPX(showGPX("2021R4R/2021_RMHCCF_5K_(updated)_40nodes.gpx", "pink", 4, 0.3))
]]

		addGPX(showGPX("2022TDC/2020_TdC_-101_Mi_538nodes.gpx", "green", 16, 0.5))
		addGPX(showGPX("2022TDC/2020_TdC_-_63_Mi_366nodes.gpx", "blue", 12, 0.4))
		addGPX(showGPX("2022TDC/2020_TdC_-_50_Mi_208nodes.gpx", "purple", 8, 0.3))
		addGPX(showGPX("2022TDC/2020_TdC_-_25_Mi_358nodes.gpx", "deeppink", 4, 0.3))
		addGPX(showGPX("2022TDC/2020_TdC_-_10_Mi_Walgreens_Family_Ride_200nodes.gpx", "pink", 4, 0.3))

		--addGPX(showGPX("Camino-de-Santiago-SWC-Camino-1.gpx", "deeppink", 16, 0.5))

		--addGPX(showGPX("FloridaTrail/fseprd540663.gpx", "darkblue", 16, 0.5))

local at = {
--"appalachian-trail-01-georgia.gpx",
--"appalachian-trail-02-north-carolina-and-tennessee.gpx",
--"appalachian-trail-03-virginia-part-1-south-to-waynesboro-brk.gpx",
--"appalachian-trail-04-virginia-part-2-waynesboro-north.gpx",
--"appalachian-trail-05-west-virginia-and-maryland.gpx",
--"appalachian-trail-06-pennsylvania.gpx",
--"appalachian-trail-07-new-jersey.gpx",
--"appalachian-trail-08-new-york.gpx",
--"appalachian-trail-09-connecticut.gpx",
"appalachian-trail-10-massachusettes.gpx",
"appalachian-trail-11-vermont.gpx",
"appalachian-trail-12-new-hampshire.gpx",
"appalachian-trail-13-maine.gpx"
}
		for i, m in ipairs(at) do
			--addGPX(showGPX("AT/"..m, "green", 16, 0.5))
		end
	
-- Panama City
--		addGPX(showGPX("mapstogpx20180928_022052.gpx", "crimson", 7, 0.6))
--		addGPX(showGPX("mapstogpx20180928_022031.gpx", "crimson", 7, 0.6))
		
--		addGPX(showGPX("HomeConyersGatlinburgOpenRoute.gpx", "crimson", 7, 0.6))
--		table.insert(gpxFiles,showGPX("HomeConyersGatlinburgOpenRoute.gpx", "crimson", 9, 0.4))

		print("done loading GPXs")
		hideGPXs()
	end)
	--gpxFiles[#gpxFiles+1] = showGPX("TripleN.gpx", "crimson", 9)

--	gpxFiles[#gpxFiles+1] = showGPX("PA-East-1000-1000.gpx", "darkcyan", 6, 1)
--	gpxFiles[#gpxFiles+1] = showGPX("PA-West-1000-1000.gpx", "crimson", 3, 1)

end

--[[

function osmTiles:getCenter()
	return tileGroup.lat, tileGroup.lon, zoom

function osmTiles:rangeLatLon(radius)
	if not radius then radius = math.min(tileGroup.width, tileGroup.height)/2 end	-- radius is 1/2 min dimension
	radius = radius / 2	-- +/- means use 1/2 radius in each direction
	local latPerY, lonPerX = osmTiles:pixelLatLon()
	local fromPoint = LatLon.new(tileGroup.lat-radius*latPerY, tileGroup.lon)
	local toPoint = LatLon.new(tileGroup.lat+radius*latPerY, tileGroup.lon)
	local vertDistance = kmToMiles(fromPoint.distanceTo(toPoint))
	--local vertBearing = fromPoint.bearingTo(toPoint)
	fromPoint = LatLon.new(tileGroup.lat, tileGroup.lon-radius*lonPerX)
	toPoint = LatLon.new(tileGroup.lat, tileGroup.lon+radius*lonPerX)
	local horzDistance = kmToMiles(fromPoint.distanceTo(toPoint))
	--local horzBearing = fromPoint.bearingTo(toPoint)
	return horzDistance, vertDistance
end
self.distanceTo = function(point, precision)
self.bearingTo = function(point)
self.destinationPoint = function(brng, dist)	/* Dist in km */
function milesToKm(v)
function kmToMiles(v)
]]
local capFrame = 0
local function gpxWalker(polies)

	local startTiles = osmTiles:getTilesLoaded()

	print("gpxWalker:"..polies.name)
	
	for _, gpx in ipairs(polies) do
		local i = 1
		
		local wasLat, wasLon = gpx[i], gpx[i+1]
		osmTiles:moveTo(wasLat, wasLon)	-- Jump to the starting point

		while i < #gpx do
		
			while osmTiles:getQueueStats() > 0 do
--			repeat
--print("gpxWalker:"..polies.name..":Waiting for "..tostring(osmTiles:getQueueStats()).." tiles")
				local timer = MOAITimer.new()
				timer:setSpan(200/1000)
				MOAICoroutine.blockOnAction(timer:start())
				
				
				--break	-- Don't wait for queue to empty!
				
				
--print("gpxWalker:"..polies.name..":Checking "..tostring(osmTiles:getQueueStats()).." tiles")
--				coroutine.yield()
--			until osmTiles:getQueueStats() <= 0 
			end

			local tolat, tolon = wasLat, wasLon
			local atlat, atlon = osmTiles:getCenter()
			if atlat ~= tolat or atlon ~= tolon then	-- Only keep going if no one panned the map!
				toast.new(gpx.name.." Aborted!  "..tostring(osmTiles:getTilesLoaded()-startTiles).." Loaded")
				return
			end

			local delayTime = 500
			tolat, tolon = gpx[i], gpx[i+1]
			local hRange, vRange = osmTiles:rangeLatLon()
			local mRange = math.min(hRange,vRange)
			local atPoint = LatLon.new(atlat, atlon)
			local toPoint = LatLon.new(tolat, tolon)
			local dist = kmToMiles(atPoint.distanceTo(toPoint))
			if dist > mRange/2 then	-- Goes outside circle, adjust along path
				local bearing = atPoint.bearingTo(toPoint)
				local usePoint = atPoint.destinationPoint(bearing, milesToKm(mRange/2))
				print("gpxWalker:"..polies.name..":Split distance, "..tostring(dist).." too far, using "..tostring(mRange))
				tolat, tolon = usePoint.getlat(), usePoint.getlon()
			else
				local j
				local mDist = dist	-- remember the furthest we moved away
				i = i + 2	-- We made it to this point!
				for j=i,#gpx,2 do
					local tlat, tlon = gpx[j], gpx[j+1]
					local tPoint = LatLon.new(tlat,tlon)
					local tDist = kmToMiles(atPoint.distanceTo(tPoint))
					if tDist > mRange/4 or tDist < mDist then	-- Don't let it go too far or get closer
						if j > i then	-- Make sure we're skipping at least one
							i = j		-- Pick up at this point next time
							j = j - 2	-- Back to the previoulsy ok point
							tolat, tolon = gpx[j], gpx[j+1]
						end
						delayTime = delayTime / 2
						break
					end
					mDist = tDist
				end
			end
--				MOAIRenderMgr.grabNextFrame ( MOAIImage.new(), function ( img )
--																	img:write ( string.format("cap%06d.png",capFrame) )
--																	capFrame = capFrame + 1
--																	osmTiles:moveTo(tolat, tolon)
--																end )
--				osmTiles:moveTo(tolat, tolon)
			local tstart = MOAISim.getDeviceTime()
			osmTiles:moveTo(tolat, tolon)
			local tqueueCount = osmTiles:getQueueStats()
			local telapsed = (MOAISim.getDeviceTime() - tstart) * 1000

			toPoint = LatLon.new(tolat, tolon)
			local addDist = kmToMiles(atPoint.distanceTo(toPoint))

print("gpxWalker:"..polies.name..":Moving "..tostring(i).."/"..tostring(#gpx).." ("..string.format("%i",addDist*5280).."ft) queued "..tostring(tqueueCount).." tiles in "..string.format("%.0f", telapsed).."ms")

			local queueCount = osmTiles:getQueueStats()
			if queueCount <= 0 then delayTime = delayTime / 5
			elseif queueCount <= 4 then delayTime = delayTime / 2
			end
			--delayTime = 100
--print("gpxWalker"..polies.name..":Delay "..tostring(delayTime).." for "..tostring(queueCount))
--			performWithDelay(delayTime, function() gpxWalker(gpx,i,tolat,tolon,startTiles) end)
			wasLat, wasLon = tolat, tolon
			osmTiles:showCrosshair()
			
--print("gpxWalker:"..polies.name..":Delay "..tostring(delayTime).." for "..tostring(queueCount))
			local timer = MOAITimer.new()
			timer:setSpan(delayTime/1000)
			MOAICoroutine.blockOnAction(timer:start())
--print("gpxWalker:"..polies.name..":Awake "..tostring(delayTime).." after "..tostring(queueCount))
--			coroutine.yield()

		end
	
	end
	toast.new(polies.name.." Complete!  "..tostring(osmTiles:getTilesLoaded()-startTiles).." Loaded "..string.format("%.1f",polies.odometer).." miles")
end

local function walkGPX(g)
	if g > 0 and g <= #gpxFiles then
		local gpx = gpxFiles[g]
		toast.new("Walking "..gpx.name, 5000)
		MOAICoroutine.new():run( function () gpxWalker(gpx) end )
	end
end

function onResume()
    print("APRSmap:onResume()")
	if Application.viewWidth ~= myWidth or Application.viewHeight ~= myHeight then
		print("APRSmap:onResume():Resizing...")
		resizeHandler(Application.viewWidth, Application.viewHeight)
	end
	runQSOsButton(layer, Application.viewWidth, Application.viewHeight)
end

function onPause()
    print("APRSmap:onPause()")
end

function onStop()
    print("APRSmap:onStop()")
end

function onDestroy()
    print("APRSmap:onDestroy()")
end

function onEnterFrame()
    --print("onEnterFrame()")
end

function onKeyDown(event)
    print("APRSmap:onKeyDown(event)")
	print(printableTable("KeyDown",event))
	if event.key then
		print("processing key "..tostring(event.key))
		if event.key == 615 or event.key == 296 then	-- Down, zoom out
			osmTiles:deltaZoom(-1)
		elseif event.key == 613 or event.key == 294 then	-- Up, zoom in
			osmTiles:deltaZoom(1)
		elseif event.key == 609 or event.key == 290 then	-- Page Down, zoom out
			osmTiles:deltaZoom(-3)
		elseif event.key == 608 or event.key == 289 then	-- Page Up, zoom in
			osmTiles:deltaZoom(3)
		elseif event.key == 612 or event.key == 293 then	-- Left, fade out
			osmTiles:deltaTileAlpha(-0.1)
		elseif event.key == 614 or event.key == 295 then	-- Right, fade in
			osmTiles:deltaTileAlpha(0.1)
		elseif event.key == 112 then		-- P = Print
			MOAIRenderMgr.grabNextFrame ( MOAIImage.new(), function ( img ) img:write ( 'APRSISMO-capture.png' ) end )
		end
	end
end

function onKeyUp(event)
    print("APRSmap:onKeyUp(event)")
	print(printableTable("KeyUp",event))
end

local touchDowns = {}
local startPinchD = 0
local pinchDelta = 120*config.Screen.scale

local function getTouchCount()
	if MOAIInputMgr.device.touch then
		if MOAIInputMgr.device.touch.countTouches then
			return MOAIInputMgr.device.touch:countTouches()
		elseif MOAIInputMgr.device.touch.getActiveTouches then
			local touches = {MOAIInputMgr.device.touch:getActiveTouches()}
			return #touches
		end
	end
	return 0
end

function pinchDistance()
	local touches = {MOAIInputMgr.device.touch:getActiveTouches()}
	if #touches == 2 then
		local x1, y1, t1 = MOAIInputMgr.device.touch:getTouch(touches[1])
		local x2, y2, t2 = MOAIInputMgr.device.touch:getTouch(touches[2])
		local dx, dy = x2-x1, y2-y1
		local d = math.sqrt(dx*dx+dy*dy)
--print(string.format("APRSmap:onTouchMove:dx=%i dy=%i d=%i", dx, dy, d))
		return d
	end
	return nil
end

function onTouchDown(event)
	local touchCount = getTouchCount()
	local wx, wy = layer:wndToWorld(event.x, event.y, 0)
    print("APRSmap:onTouchDown(event)["..tostring(event.idx).."]@"..tostring(wx)..','..tostring(wy).." "..tostring(touchCount).." touches")
--    print("APRSmap:onTouchDown(event)["..tostring(event.idx).."]@"..tostring(wx)..','..tostring(wy)..printableTable(' onTouchDown', event))
	touchDowns[event.idx] = {x=event.x, y=event.y}
	if touchCount == 2 then
		startPinchD = pinchDistance()
	else
--		osmTiles:getTileGroup():setScl(1,1,1)
		tileLayer:setLoc(0,0)
		tileLayer:setScl(1,1,1)
	end
end

function onTouchUp(event)
	local touchCount = getTouchCount()
	local wx, wy = layer:wndToWorld(event.x, event.y, 0)
    print("APRSmap:onTouchUp(event)["..tostring(event.idx).."]@"..tostring(wx)..','..tostring(wy).." "..tostring(touchCount).." touches")
--    print("APRSmap:onTouchUp(event)["..tostring(event.idx).."]@"..tostring(wx)..','..tostring(wy)..printableTable(' onTouchUp', event))
	if touchDowns[event.idx] then
		local dy = event.y - touchDowns[event.idx].y
		if math.abs(dy) > Application.viewHeight * 0.10 then
			local dz = 1
			if dy > 0 then dz = -1 end
--[[			osmTiles:deltaZoom(dz)
		else
			config.lastDim = not config.lastDim
			if config.lastDim then	-- Dim
				backLayer:setClearColor ( 0,0,0,1 )	-- Black background
			else	-- Bright
				backLayer:setClearColor ( 1,1,1,1 )	-- White background
			end
]]		end
	end
--[[
		local props = {layer:getPartition():propListForPoint(wx, wy, 0, sortMode)}
		for i = #props, 1, -1 do
			local prop = props[i]
			if prop:getAttr(MOAIProp.ATTR_VISIBLE) > 0 then
				print('APRSmap:Found prop..'..tostring(prop)..' with '..tostring(type(prop.onTap)))
			end
		end
]]
--    SceneManager:closeScene({animation = "popOut"})
	touchDowns[event.idx] = nil
	local count = 0
	for i,t in pairs(touchDowns) do
		count = count + 1
	end
	if touchCount ~= 2 or count ~= 2 then
--		osmTiles:getTileGroup():setScl(1,1,1)
		tileLayer:setLoc(0,0)
		tileLayer:setScl(1,1,1)
	end
end

function onTouchMove(event)
	local touchCount = getTouchCount()
	if touchDowns[event.idx] then
		local dx = (event.x - touchDowns[event.idx].x)
		local dy = (event.y - touchDowns[event.idx].y)
--		print(string.format('APRSmap:onTouchMove:dx=%i dy=%i moveX=%i moveY=%i (%i touches)', dx, dy, event.moveX, event.moveY, touchCount))
		if touchCount <= 1 then
			osmTiles:deltaMove(event.moveX, event.moveY)
		elseif touchCount == 2 then
			local touches = {MOAIInputMgr.device.touch:getActiveTouches()}
			if #touches == 2 then
				local x1, y1, t1 = MOAIInputMgr.device.touch:getTouch(touches[1])
				local x2, y2, t2 = MOAIInputMgr.device.touch:getTouch(touches[2])
				local dx, dy = x2-x1, y2-y1
				local d = math.sqrt(dx*dx+dy*dy)
				local delta = d-startPinchD
--print(string.format("APRSmap:onTouchMove:dx=%i dy=%i d=%.2f vs %.2f Delta=%.2f", dx, dy, d, startPinchD, delta))
				if math.abs(math.modf(delta/pinchDelta)) >= 1 then
					osmTiles:deltaZoom(math.modf(delta/pinchDelta))
					startPinchD = startPinchD + math.modf(delta/pinchDelta)*pinchDelta
				end
				local scale = 2^((d-startPinchD)/pinchDelta)
				tileLayer:setScl(scale,scale,1)
				local width, height = tileLayer:getSize()
				local nw, nh = width*scale, height*scale
--print(string.format('APRSmap:onTouchMove: %i x %i *%.2f %i x %i off:%i %i', width, height, scale, nw, nh, xo, yo))
				tileLayer:setLoc((width-nw)/2,(height-nh)/2)
			end
		end
	end
end

local objectCounts

function onCreate(e)
	print('APRSmap:onCreate')
--[[
do
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,:;!?()&/-"
	local index = 1
	local sprite, temptext, sizetext
	local paused = false
	performWithDelay(1000, function()
	if not paused then
	local c = chars:sub(index,index)
	index = index + 1
	if index > #chars then index = 1 end
	if sprite then sprite:dispose() end
	if sizetext then sizetext:dispose() end
	if temptext then temptext:dispose() end
	print("Doing:"..c)
	local font = FontManager:getRecentFont()
	local fontImage, xBearing, yBearing = font:getGlyphImage(c, 18*.7)
	if fontImage then
		local width, height = fontImage:getSize()
		fontImage:drawLine(0,yBearing,width-1,yBearing,0,0,0,1.0)
		fontImage:drawLine(0,yBearing+1,width-1,yBearing+1,0,0,0,1.0)
		fontImage:drawLine(0,height-1,width-1,height-1,0,0,0,1.0)
		fontImage:drawLine(xBearing,0,xBearing,height-1,0,0,0,1.0)
		sprite = Sprite{texture=fontImage, layer=layer}
		print("getGlyphImage("..c..") returned "..tostring(fontImage).." size "..sprite:getWidth().." x "..sprite:getHeight().." Bearing:"..xBearing.." "..yBearing)
		--sprite:setColor(1,0,0,0.5)
		sprite:setLeft(0) sprite:setTop(titleBackground:getBottom())
		sprite:addEventListener( "touchUp", function() paused = not paused end )
	sizetext = TextLabel { text=tostring(width)..'x'..tostring(height)..' '..tostring(xBearing)..' '..tostring(yBearing), layer=layer }
	sizetext:setColor(0,0,0, 1.0)
	sizetext:fitSize()
	sizetext:setLeft(sprite:getRight()) sizetext:setTop(sprite:getTop()+sprite:getHeight()/2)

	end
	temptext = TextLabel { text=c..".", layer=layer, textSize=18*.7 }
	temptext:setColor(0,0,0, 1.0)
	temptext:fitSize()
	temptext:setLeft(0) temptext:setTop(sprite:getBottom())
	end
	end, 0)
end
]]

	print("APRSmap:setting APRS callbacks")
	APRS:addReceiveListener(stations.packetReceived)

	print("APRSmap:setting APRSIS callbacks")
	APRSIS:setAppName(MOAIEnvironment.appDisplayName,MOAIEnvironment.appVersion)
	APRSIS:addPacketCallback(function(line, port) APRS:received(line,port) end)	-- Tie the two together!
	APRSIS:addConnectedCallback(function(clientServer)
									print("APRSmap:APRSIS:connected:"..tostring(clientServer))
									if config.APRSIS.Notify then toast.new(tostring(clientServer), 2000) end
									end)
	APRSIS:addStatusCallback(function(status) _G["lwdUpdate"] = status end)
	print("APRSmap:Done setting APRSIS callbacks")

	local width, height = Application.viewWidth, Application.viewHeight
	myWidth, myHeight = width, height

	print("APRSmap:resizeHandler="..tostring(resizeHandler))
	scene.getGPXs = getGPXs
	scene.countGPX = countGPX
	scene.walkGPX = walkGPX
	scene.isGPXVisible = isGPXVisible
	scene.showGPXs = showGPXs
	scene.hideGPXs = hideGPXs
	scene.resizeHandler = resizeHandler
	scene.menuHandler = function()
							SceneManager:openScene("buttons_scene", {animation="overlay"})
						end

	APRSmap.backLayer = Layer {scene = scene }
	if type(APRSmap.backLayer.setClearColor) == 'function' then 
	if config.lastDim then	-- Dim
		APRSmap.backLayer:setClearColor ( 0,0,0,1 )	-- Black background
	else	-- Bright
		APRSmap.backLayer:setClearColor ( 1,1,1,1 )	-- White background
	end
	else print('setClearColor='..type(APRSmap.backLayer.setClearColor))
	end

	tileLayer = Layer { scene = scene, touchEnabled = true }
	--tileLayer:setAlpha(0.9)
	local alpha = 0.75
	alpha = 1.0
	tileLayer:setColor(alpha,alpha,alpha,alpha)
	osmTiles:getTileGroup():setLayer(tileLayer)

    layer = Layer {scene = scene, touchEnabled = true }
	local textColor = {0,0,0,1}

	if config.Debug.ShowAccel then
	--	stilltext = TextLabel { text="nil\n hh:mm:ss. ", layer=layer, textSize=28*config.Screen.scale }
		stilltext = TextBackground { text="nil\n hh:mm:ss. ", layer=layer, textSize=28*config.Screen.scale }
	_G["stilltext"] = stilltext
		stilltext:setColor(unpack(textColor))
		stilltext:fitSize()
		stilltext:setAlignment ( MOAITextBox.LEFT_JUSTIFY )
		stilltext:setLoc(stilltext:getWidth()/2+config.Screen.scale, height-stilltext:getHeight()/2)		--0*config.Screen.scale)
		stilltext:setPriority(2000000000)
	end
	
--	lwdtext = TextLabel { text="lwdText", layer=layer, textSize=20*config.Screen.scale }
	lwdtext = TextBackground { text="lwdText", layer=layer, textSize=math.floor(20*config.Screen.scale+0.5) }
--	local font = MOAIFont.new ()
--	if Application:isDesktop() then
--		font:load ( "cour.ttf" )
--	else
--		font:load ( "courbd.ttf" )
--	end
--	lwdtext:setFont(font)
--	lwdtext:setBackgroundRGBA(0.75, 0.75, 0.75, 0.75)
_G["lwdtext"] = lwdtext
--	lwdtext:setColor(0.25, 0.25, 0.25, 1.0)
	lwdtext:setColor(unpack(textColor))
--	lwdtext:setBackgroundRGBA(0.25, 0.25, 0.25, 0.25)
	lwdtext:fitSize()
	--lwdtext:setWidth(width)
	lwdtext:setAlignment ( MOAITextBox.CENTER_JUSTIFY )	-- Was CENTER_JUSTIFY (LEFT might fix dropped trailer)
	lwdtext:setLoc(width/2, 75*config.Screen.scale)
local x,y = lwdtext:getSize()
	lwdtext:setPriority(2000000000)

if MOAIAppAndroid and type(MOAIAppAndroid.setBluetoothDevice) == 'function' then
if MOAIAppAndroid and type(MOAIAppAndroid.setBluetoothEnabled) == 'function' then
	if config.Bluetooth and config.Bluetooth.Device ~= '' then
		kisstext = TextBackground { text="KISS Placeholder", layer=layer, textSize=20*config.Screen.scale }
	_G["kisstext"] = kisstext
		kisstext:setColor(unpack(textColor))
		kisstext:fitSize()
		--kisstext:setWidth(width)
		kisstext:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
		kisstext:setLoc(width/2, 95*config.Screen.scale)
	local x,y = kisstext:getSize()
		kisstext:setPriority(2000000000)
	end
end
end

if config.Debug.ShowIPFS then
	IPFStext = TextBackground { text="IPFS Placeholder 1\n2\n3\n4\n5", layer=layer, textSize=18*config.Screen.scale }
_G["IPFStext"] = IPFStext
	IPFStext:setColor(unpack(textColor))
	IPFStext:fitSize()
	--IPFStext:setWidth(width)
	IPFStext:setAlignment ( MOAITextBox.LEFT_JUSTIFY )
	IPFStext:setLoc(width/2, 95*config.Screen.scale)
local x,y = IPFStext:getSize()
	IPFStext:setPriority(2000000000)
end

--	if config.StationID:sub(1,6) == 'KJ4ERJ' then

if config.StationID == "KJ4ERJ-DVx" then

	local fileText

	local function showFile(name)
		print("Showing "..name)
		--recentImage = Sprite {texture = "2018-11-24 10.05.18.jpg", layer = layer, left = 0, top = 0}
		
--	if fileText then fileText:dispose(); fileText = nil; end

	if not fileText then
		fileText = TextBackground { text=name, layer=layer, textSize=20*config.Screen.scale }
	else fileText:setString(name)
	end
	fileText:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	fileText:setColor(unpack(textColor))
	fileText:setPriority(2000000001)
	fileText:setLoc(width-140, height/2)

		local fullImage = MOAIImage.new()
		fullImage:load(name, MOAIImage.PREMULTIPLY_ALPHA)
		--print('recentImage is '..tostring(recentImage.OriginalXsize)..'x'..tostring(recentImage.OriginalYsize)..' screen:'..tostring(width)..'x'..tostring(height))
		local x, y = fullImage:getSize()
		recentImage = MOAIImage.new()
		--recentImage:init(x, x, fullImage:getFormat())
		recentImage:init(x, x)
		recentImage:copyRect(fullImage, 0, y/2-30-x/2, x, y/2-30+x/2, 0, 0, x, x,
								MOAIImage.FILTER_LINEAR,
								MOAIImage.BLEND_FACTOR_DST_ALPHA,
								MOAIImage.BLEND_FACTOR_ZERO)
								
		typeImage = MOAIImage.new()
		typeImage:init(144,38, fullImage:getFormat())
	--[[	typeImage:copyRect(fullImage, 938,1679, 938+144,1679+38, 0,0, 144,38,
								MOAIImage.FILTER_LINEAR,
								MOAIImage.BLEND_FACTOR_DST_ALPHA,
								MOAIImage.BLEND_FACTOR_ZERO)]]
		for xp=0, 144-1 do
			for yp=0, 38-1 do
				local r, b, g, a = fullImage:getRGBA(xp+933,yp+1678)
				local b = 0.3*r + 0.59*g + 0.11*b
				if b < 0.8 then
					typeImage:setRGBA(xp,yp,0,0,0,1)
				else typeImage:setRGBA(xp,yp,1,1,1,1)
				end
			end
		end
		typeImage = Sprite {texture=typeImage, layer=layer, left=0, top=0}
		typeImage:setPriority(2000000001)
		typeImage:setLoc(width-140, height/2-38)
		if _G["typeImage"] then _G["typeImage"]:dispose() end
		_G["typeImage"] = typeImage
								
		coordImage = MOAIImage.new()
		coordImage:init(192,16, fullImage:getFormat())
	--[[	coordImage:copyRect(fullImage, 875,1529, 875+196,1529+32-3, 0,0, 196,32,
								MOAIImage.FILTER_LINEAR,
								MOAIImage.BLEND_FACTOR_DST_ALPHA,
								MOAIImage.BLEND_FACTOR_ZERO)]]
		for xp=0, 192-1 do
			for yp=0, 16-1 do
				local r, b, g, a = fullImage:getRGBA(xp+874,yp+1535)
				local b = 0.3*r + 0.59*g + 0.11*b
				if b < 0.33 then
					coordImage:setRGBA(xp,yp,0,0,0,1)
				else coordImage:setRGBA(xp,yp,1,1,1,1)
				end
			end
		end
		coordImage = Sprite {texture=coordImage, layer=layer, left=0, top=0}
		coordImage:setPriority(2000000002)
		coordImage:setLoc(width-200, height/2+26)
		if _G["coordImage"] then _G["coordImage"]:dispose() end
		_G["coordImage"] = coordImage
		
		for xp = 0, x-1 do
	--		print("xp="..tostring(xp))
			for yp = 0, x-1 do
				--print("yp="..tostring(yp))
				local r, g, b, a = recentImage:getRGBA(xp,yp)
				--print("rgba@"..tostring(xp)..","..tostring(yp).."="..tostring(r).." "..tostring(g).." "..tostring(b).." "..tostring(a))
				if r==1.0 and g==1.0 and b==1.0 then
					--print("Transparent White at "..tostring(xp)..","..tostring(yp))
					recentImage:setRGBA(xp,yp,0,0,0,0)
				elseif r==0 and g==0 and b==0 then
					--print("Transparent Black at "..tostring(xp)..","..tostring(yp))
					recentImage:setRGBA(xp,yp,0,0,0,0)
				else
					local b = 0.3*r + 0.59*g + 0.11*b
					if b < 0.3 then
						recentImage:setRGBA(xp,yp,0,0,0,0)
					else
						local xd = xp - x/2
						local yd = yp - x/2
						local d = math.sqrt(xd*xd+yd*yd)
						if d > x/2 then
							recentImage:setRGBA(xp,yp,0,0,0,0)
						end
					end
				end
			end
		end

		recentImage = Sprite {texture=recentImage, layer=layer, left=0, top=0}
		--recentImage.lat, recentImage.lon = 26.352582, -81.786696;	-- 2018-11-24 10.05.18.jpg
		recentImage.lat, recentImage.lon = 28.082962, -80.650451;	-- 2018-11-29 16.50.46.jpg
		recentImage.lat, recentImage.lon = osmTiles:getCenter()
		recentImage.OriginalXsize, recentImage.OriginalYsize = recentImage:getSize()
		print('2018-11-29 16.50.46.jpg is '..tostring(recentImage.OriginalXsize)..'x'..tostring(recentImage.OriginalYsize)..' screen:'..tostring(width)..'x'..tostring(height))
	--	recentImage:setLoc(width/2, height/2+15)
		--recentImage:setAlpha(0.25)
		recentImage:setPriority(2000000000)
		recentImage:addEventListener("touchDown", function() print("image touched") end)
		if _G["recentImage"] then _G["recentImage"]:dispose() end
		_G["recentImage"] = recentImage

		
		local z = osmTiles:getZoom()
		local s = 2^(z-16)
		print("recentImage:zoom("..tostring(z)..") scale="..tostring(s))
		recentImage:setScl(s)
		local x,y = osmTiles:whereIS(recentImage.lat, recentImage.lon)
		if x and y then
			x,y = osmTiles:translateXY(x,y)
			print("recentImage:Moving to "..tostring(x)..","..tostring(y))
			recentImage:setLoc ( x,y )
			--recentImage:setLoc ( width/2, height/2 )
		end
	
--		end

	end
	
	local files, nextFile
	
	performWithDelay2("ScreenCaps", 1000, function()
		files = MOAIFileSystem.listFiles("D:/ResourcesScreencaps")
		if not files then files = {} end
		print("listFiles returned "..tostring(#files).." files")
		table.sort(files)
		nextFile = 1
		performWithDelay2("ShowCap", 500, function()
								if nextFile <= #files then
									local f = files[nextFile]
									print("Files["..tostring(nextFile).."]="..tostring(f))
									if f:match("^.+%.png$") or f:match("^.+%.jpg$") then
										showFile("D:/ResourcesScreencaps/"..f)
									end
									nextFile = nextFile + 1
								end
							end, 0)
	end)

--[[	osmTiles:addCallback(function (what, ...)
								print("recentImage:osmTiles said "..tostring(what))
								if what == "zoom" then
									local z = osmTiles:getZoom()
									local s = 2^(z-16)
									print("recentImage:zoom("..tostring(z)..") scale="..tostring(s))
									recentImage:setScl(s)
								end
								local x,y = osmTiles:whereIS(recentImage.lat, recentImage.lon)
								if x and y then
									x,y = osmTiles:translateXY(x,y)
									print("recentImage:Moving to "..tostring(x)..","..tostring(y))
									recentImage:setLoc ( x,y )
									--recentImage:setLoc ( width/2, height/2 )
								end
						end)]]
end

		temptext = TextBackground { text="tempText", layer=layer, textSize=24*config.Screen.scale }
		local font = MOAIFont.new ()
		if Application:isDesktop() then
			font:load ( "cour.ttf" )
		else
			font:load ( "courbd.ttf" )
		end
		temptext:setFont(font)
	_G["temptext"] = temptext
		temptext:setColor(unpack(textColor))
		temptext:fitSize()
		temptext:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
		temptext:setLoc(width/2, height/2)
		temptext:setPriority(2000000000)
--	end

	if config.Debug.RunProxy then
		pxytext = TextBackground { text="pxyText", layer=layer, textSize=20*config.Screen.scale }
	_G["pxytext"] = pxytext
		pxytext:setColor(unpack(textColor))
		pxytext:fitSize()
		--pxytext:setWidth(width)
		pxytext:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
		pxytext:setLoc(width/2, 95*config.Screen.scale)
	local x,y = pxytext:getSize()
		pxytext:setPriority(2000000000)
	end

	whytext = TextBackground { text="whyText", layer=layer, textSize=32*config.Screen.scale }
_G["whytext"] = whytext
	whytext:setColor(unpack(textColor)) --0.5, 0.5, 0.5, 1.0)
	whytext:fitSize()
	--whytext:setWidth(width)
	whytext:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	whytext:setLoc(width/2, height-32*config.Screen.scale)
local x,y = whytext:getSize()
	whytext:setPriority(2000000000)
	
	gpstext = TextBackground { text="gpsText", layer=layer, textSize=22*config.Screen.scale }
_G["gpstext"] = gpstext
	gpstext:setColor(unpack(textColor)) --0.5, 0.5, 0.5, 1.0)
	gpstext:fitSize()
	gpstext:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	gpstext:setLoc(width/2, height-65*config.Screen.scale)
	gpstext:setPriority(2000000000)

	speedtext = TextLabel { text="1999", layer=layer, textSize=80*config.Screen.scale, align={"center","top"} }
_G["speedtext"] = speedtext
	speedtext:setColor(unpack(textColor))
	speedtext:fitSize()
	--speedtext:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	speedtext:setRight(width) speedtext:setTop(125*config.Screen.scale)
	--speedtext:setLoc(width/2, height-65*config.Screen.scale)
	speedtext:setPriority(2000000000)
	speedtext:setString("")
	speedtext:addEventListener('touchUp', function() print("speed touched!") end)
--[[	performWithDelay(1000,function()
			local speed = math.random(0,110)
			if speed < 10 then speed = string.format("%.1f",speed) else speed = tostring(math.floor(speed)) end
			print("new speed="..speed)
			speedtext:setString(speed)
		end, 0)
]]

	odotext = TextBackground { text="9999.9", layer=layer, textSize=32*config.Screen.scale, align={"center","top"} }
_G["odotext"] = odotext
	odotext:setColor(unpack(textColor))
	odotext:fitSize()
	--odotext:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	odotext:setRight(width) odotext:setTop(speedtext:getBottom())
	--odotext:setLoc(width/2, height-65*config.Screen.scale)
	odotext:setPriority(2000000000)
	odotext:setString("")
	odotext:addEventListener('touchUp', function() print("odometer touched!") end)
	local odometer = 0
--[[	performWithDelay(1000,function()
			odometer = odometer + math.random(0,110)/100
			odotext:setString(string.format("%.1f",odometer))
		end, 0)]]

	memoryText = TextBackground { text="memoryText", layer=layer, textSize=20*config.Screen.scale }
	memoryText:setColor(unpack(textColor))
	memoryText:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	memoryText:setLoc(width/2, 55*config.Screen.scale)
--	memoryText:setPriority(2000000000)
	memoryText:setPriority(1999999999)
	memoryText:addEventListener("touchUp",
			function()
				print("Collecting Garbage")
if Application:isDesktop() then
				stations:clearStations()
end
				MOAISim:forceGarbageCollection()	-- This does it iteratively!
if Application:isDesktop() then
	print ( "REPORTING HISTOGRAM" )
	if type(MOAISim.reportHistrogram) == 'function' then MOAISim.reportHistogram () end
	if type(MOAISim.reportLeaks) == 'function' then MOAISim.reportLeaks(true) end	-- report leaks and reset the bar for next time
	print ()
	
	if not objectCounts then objectCounts = {} end
	local didOne = false
	if type(MOAISim.getHistogram) == 'function' then
		local histogram = MOAISim.getHistogram ()
		for k, v in pairs ( histogram ) do
			if objectCounts[k] and objectCounts[k] ~= v then
				print('memoryText:Delta('..tostring(v-objectCounts[k])..') '..k..' objects')
				didOne = true
			end
			objectCounts[k] = v
		end
		if didOne then print() end
	end
end
				print("memoryText:touchUp\n")
				updateMemoryUsage()
			end)

			
    titleGroup = Group { layer=layer }
	titleGroup:setLayer(layer)

	titleGradientColors = { "#BDCBDC", "#BDCBDC", "#897498", "#897498" }
--	local colors = { "#DCCBBD", "#DCCBBD", "#987489", "#987489" }
 --	{ 189, 203, 220, 255 }, 
--	{ 89, 116, 152, 255 }, "down" )

    -- Parameters: left, top, width, height, colors
    --titleBackground = Mesh.newRect(0, 0, width, 40, titleGradientColors )
	titleBackground = Graphics {width = width, height = 40*config.Screen.scale, left = 0, top = 0}
    --titleBackground:setPenColor(0.707, 0.8125, 0.8125, 0.75):fillRect()	-- 181,208,208 from OSM zoom 0 map
    titleBackground:setPenColor(0.25, 0.25, 0.25, 0.75):fillRect()	-- dark gray like Android
	titleBackground:setPriority(2000000000)
	titleGroup:addChild(titleBackground)

	titleText = TextLabel { text="APRSISMO", textSize=28*config.Screen.scale }
	titleText:fitSize()
	titleText:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	titleText:setLoc(width/2, 20*config.Screen.scale)
	titleText:setPriority(2000000001)
	titleGroup:addChild(titleText)
	--titleGroup:setRGBA(1,1,1,0.75)
_G["titleText"] = titleText

    --titleGroup:resizeForChildren()
	--titleGroup:setLoc(0,0)
	titleGroup:addEventListener("touchUp",
			function()
				print("Tapped TitleGroup")
				scene.menuHandler()
--[[
				local text = tostring(MOAIEnvironment.appDisplayName)..' '..tostring(MOAIEnvironment.appVersion)
				text = text..' @ '..tostring(MOAIEnvironment.screenDpi)..'dpi'
				text = text..'\r\ncache:'..tostring(MOAIEnvironment.cacheDirectory)
				text = text..'\r\ndocument:'..tostring(MOAIEnvironment.documentDirectory)
				text = text..'\r\nextCache:'..tostring(MOAIEnvironment.externalCacheDirectory)
				text = text..'\r\nextFiles:'..tostring(MOAIEnvironment.externalFilesDirectory)
				text = text..'\r\nresource:'..tostring(MOAIEnvironment.resourceDirectory)
				toast.new(text)
				print(text)
]]
			end)
			
	performWithDelay(1000, function()
		updateCommands()	-- get the config applied
		updateBluetooth()	-- get the config applied
		updateGPSEnabled()	-- get the config applied
		updateKeepAwake()	-- get the config applied
		updateTelemetryEnabled()	-- get the config applied
	end)
	
--[[
	testWedge = Graphics { layer=layer, left=0, top=0, width=100, height=100 }
	testWedge:setPenColor(0,0,0,0.25):setPenWidth(1):fillFan({0,0,100,90,90,100,75,200,0,0})
	--testWedge:setScl(2,2,2)
	testWedge:setPriority(3000000)
]]

	local temps = {}
	local function ctof(v) return v/10*9/5+32 end
	local function addTemp(stationID, which, name, convert, fmt)
		table.insert(temps,{ID=stationID, which=which, name=name, f=(convert or ctof), fmt=(fmt or "%4.1f")})
	end

	if config.StationID:sub(1,6) == 'KJ4ERJ'
--	and config.StationID ~= "KJ4ERJ-TS"
	and config.StationID ~= "KJ4ERJ-LS" then

		addTemp("KJ4ERJ-NR", 1, "Naylor", function(v) return v/10 end)
		addTemp("KJ4ERJ-TD", 1, "Power", function(v) return v/10 end)
		addTemp("KJ4ERJ-S1", 3, "Server")
		addTemp("KJ4ERJ-E1", 3, "Return")
		addTemp("KJ4ERJ-E1", 4, "Kitchen")
		addTemp("KJ4ERJ-E1", 5, "Thermo")
		addTemp("KJ4ERJ-TD", 5, "TEDTemp", function(v) return v/10 end)
		addTemp("KJ4ERJ-E2", 3, "Fridge")
		addTemp("KJ4ERJ-E2", 4, "Kitchen")
		addTemp("KJ4ERJ-E2", 5, "Freezer")
		addTemp("KJ4ERJ-E3", 4, "Family")
		addTemp("KJ4ERJ-MB", 3, "Master")
		addTemp("KJ4ERJ-HW", 3, "Garage")
		addTemp("KJ4ERJ-HP", 3, "Butter")
		addTemp("KJ4ERJ-E3", 3, "Water")
		addTemp("KJ4ERJ-LS", 1, "GSZones", function(v) return v end, "%4d")
		addTemp("KJ4ERJ-LS", 2, "Strikes", function(v) return v*5 end, "%4d")
		addTemp("KJ4ERJ-LS", 3, "Squares", function(v) return v*4 end, "%4d")

	end
	local function showTelemetry()
		if config.lastTemps then
			local text = ""
			if config.StationID:sub(1,6) == 'KJ4ERJ'
			and (config.lastTemps == 8
				or not MOAIAppAndroid and config.lastTemps == 7) then
				local function elapsed(now, when)
					local delta = now - when
					local result = ""
					if delta <= 99 then
						result = tostring(delta).."s"
					elseif delta <= 90*60 then
						result = tostring(math.floor(delta/60)).."m"
						if delta%60 > 0 then result = result.."+" end
					elseif delta < 24*60*60 then
						result = tostring(math.floor(delta/60/60)).."h"
						if delta%3600 > 0 then result = result.."+" end
					else
						result = tostring(math.floor(delta/24/60/60)).."d"
						if delta%(24*60*60) > 0 then result = result.."+" end
					end
					while #result < 5 do
						result = " "..result
					end
					return result
				end
				local now = os.time()
				for x,i in ipairs(temps) do

					if stationInfo[i.ID] and stationInfo[i.ID].telemetry then
						local station = stationInfo[i.ID]
						text = text..string.format("%s[%3d] %7s %s %d %s\n",
										i.ID:sub(-2,-1), station.telemetry.seq,
										i.name,
										string.format(i.fmt, i.f(station.telemetry.values[i.which])),
										station.telemetryPackets,
										elapsed(now, station.telemetryTime))
					end
				end
--[[				
				if NaylorTemp then
					text = text..string.format("Naylor A/C Vent %s %d %s\n",
									string.format("%4.1f", NaylorTemp.F),
									NaylorTemp.Pkts,
									elapsed(now, NaylorTemp.When))
				end
]]
			elseif MOAIAppAndroid and config.lastTemps == 7 then
				local function addIf(which)
					local key = "Battery"..which
					if type(MOAIEnvironment[key]) ~= 'nil' then
						text = text..string.format("%s: %s\n", which, tostring(MOAIEnvironment[key]))
					end
				end
				for _, v in pairs({"Percent", "Health", "Status", "Plugged", "ChargeRate", "Technology", "Temperature", "Voltage"}) do
					addIf(v)
				end
				if text == '' then text = "No Battery Statistics"
				else text = 'Battery Status\n'..text end
			elseif config.lastTemps == 6 then
				text = formatChoices()
			elseif config.lastTemps == 5 then
				text = formatGatewayCounts(0)	-- All
			elseif config.lastTemps == 4 then
				text = formatGatewayCounts(-1)	-- Bad
			elseif config.lastTemps == 3 then
				text = formatGatewayCounts(1)	-- Good
			elseif config.lastTemps == 2 then
				text = formatIPFSContents()	-- IPFS Has
			else
				local function compare(one,two)
					if type(one) == 'number' and type(two) == 'number' then
						return one < two
					else return tostring(one) < tostring(two)
					end
				end
				local function human(c)
					if c < 1000 then
						return tostring(c)
					elseif c < 10*1000 then
						return string.format("%.2fK", c/1000)
					elseif c < 100*1000 then
						return string.format("%.1fK", c/1000)
					elseif c < 1000*1000 then
						return string.format("%.0fK", c/1000)

					elseif c < 10*1000*1000 then
						return string.format("%.2fM", c/1000/1000)
					elseif c < 100*1000*1000 then
						return string.format("%.1fM", c/1000/1000)
					elseif c < 1000*1000*1000 then
						return string.format("%.0fM", c/1000/1000)
						
					elseif c < 10*1000*1000*1000 then
						return string.format("%.2fB", c/1000/1000/1000)
					elseif c < 100*1000*1000*1000 then
						return string.format("%.1fB", c/1000/1000/1000)
					elseif c < 1000*1000*1000*1000 then
						return string.format("%.0fB", c/1000/1000/1000)
						
					elseif c < 10*1000*1000*1000*1000 then
						return string.format("%.2fT", c/1000/1000/1000/1000)
					elseif c < 100*1000*1000*1000*1000 then
						return string.format("%.1fT", c/1000/1000/1000/1000)
					elseif c < 1000*1000*1000*1000*1000 then
						return string.format("%.0fT", c/1000/1000/1000/1000)
						
					else return string.format("%.0fT", c/1000/1000/1000/1000)
					end
				end
				local counts = osmTiles:getMBTilesCounts()
				if counts then
					for z, c in pairsByKeys(counts, compare) do
						if z == 'name' then
							text = c.."\n"..text
						elseif z == 'elapsed' then
							text = string.format("Count took %.2fmsec\n",c)..text
						elseif type(c) == 'table' then
							local range = 2^z
							local ztotal = range * range
							local ctotal = (c.max_y-c.min_y+1)*(c.max_x-c.min_x+1)
							local d2 = math.floor(math.log10((2^z)*(2^z))+0.999999)
							local digits = math.floor(math.log10(2^z)+0.999999)
							--[[
							local f = "%"..tostring(digits).."d"
							f = " "..f.."-"..f
							f = "%d %s %3d%%/%3d%%"..f..f.."\n"
							text = text..string.format(f, z, human(c.count), c.count/ctotal*100, ctotal/ztotal*100,
														c.min_y, c.max_y,
														c.min_x, c.max_x)]]
							local f = "%"..tostring(digits).."d"
							f = " "..f.."-"..f
							f = "%d %s %3d%%/%3d%%\n"
							text = text..string.format(f, z, human(c.count), c.count/ctotal*100, ctotal/ztotal*100)
						else text = text.."*UNKNOWN("..tostring(c)..")*\n"
						end
					end
				end
			end
			if temptext and text ~= "" and (temptext.last ~= text) then
--					print(text)
--					local x,y = temptext:getLoc()
				temptext:setString ( text );
--					temptext:fitSize()
--					temptext:setLoc(x,y)
				temptext.last = text
			end
		elseif not temptext.last or temptext.last ~= "" then
			temptext:setString ("")
			temptext.last = ""
		end
	end

	performWithDelay2("showTelemetry", 1000, showTelemetry, 0)

end
