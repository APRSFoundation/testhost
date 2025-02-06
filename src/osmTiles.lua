local debugging = false
local MaxSymbols = 1000
local concurrentLoadingThreads = 4
local delayBetweenTiles = 0 --2000

-- Project: APRSISMO
--
-- Date: Jun 19, 2013
--
-- Version: 0.1
--
-- File name: osmTiles.lua
--
-- Author: Lynn Deffenbaugh, KJ4ERJ
--
-- Abstract: Tile fetching support
--
-- Demonstrates: sockets, network
--
-- File dependencies: 
--
-- Target devices: Simulator and Device
--
-- Limitations: Requires internet access; no error checking if connection fails
--
-- Update History:
--	v0.1		Initial implementation
--
-- Comments: 
-- Uses LuaSocket libraries that ship with Corona. 
--
-- Copyright (C) 2013 Homeside Software, Inc. All Rights Reserved.
---------------------------------------------------------------------------------------
local osmTiles = { VERSION = "0.0.1" }

local tileScale = 1
local tileSize = 256*tileScale

function osmTiles:getTileScale()
	return tileScale, tileSize
end

local toast = require("toast");
local colors = require("colors");
local LatLon = require("latlon")

local tilemgr = require("tilemgr")
tilemgr:setGetTileGroup(function() return osmTiles:getTileGroup() end)

-- local busyImage
local osmLoading = {}

local zoom, zoomDiv, zoomDelta = 0, 1/(2^(20-0))*tileScale, 2^0*tileScale
local zoomMax = 20

local tileAlpha = 0.10

function osmTiles:getTileAlpha()
	return tileAlpha
end

local tileGroup = Group()	-- global for access by main (stupid, I know)
local tilesLoaded = 0		-- Count of loaded tiles

function osmTiles:getTilesLoaded()
	return tilemgr:getTilesLoaded()
end

function osmTiles:getTileGroup()
	return tileGroup
end

function osmTiles:getZoom()
	return zoom, zoomMax
end

local activeCallbacks = {}

function osmTiles:addCallback(callFunc)
	for k,v in pairs(activeCallbacks) do
		if v == callFunc then return false end
	end
	table.insert(activeCallbacks, callFunc)
	return true
end

function osmTiles:removeCallback(callFunc)
	for k,v in pairs(activeCallbacks) do
		if v == callFunc then
			activeCallbacks[k] = nil
			return true
		end
	end
	return false
end

local function invokeCallbacks(what, ...)
	for k,v in pairs(activeCallbacks) do
		v(what,...)
	end
end

local currentVersionID = 0
local function newVersionID()
	currentVersionID = currentVersionID + 1
	return currentVersionID
end

function fillTextSquare(square, text, minSize, maxSize, padWidth, padHeight)
--[[
	minSize = minSize or 1
	maxSize = maxSize or 128
	local w, h = square.contentWidth, square.contentHeight
	for f = minSize, maxSize do
		text.size = f
		-- print(string.format('size:%i %s:%ix%i square:%ix%i', f, text.text, text.contentWidth, text.contentHeight, w, h))
		if text.contentHeight > h or text.contentWidth > w then break end
	end
	text.size = text.size - 1
	return text.size
]]
	minSize = minSize or 1
	maxSize = maxSize or 128
	padWidth = padWidth or 0
	padHeight = padHeight or 0
	local w, h = square.contentWidth, square.contentHeight
	local s = 1.0
	while text.contentHeight+padHeight > h or text.contentWidth+padWidth > w do
		s = s * 0.9
		text:scale(0.9, 0.9)
		--print(string.format('scale:%i %s:%ix%i square:%ix%i', s, text.text, text.contentWidth, text.contentHeight, w, h))
	end
	--print(string.format('scale:%i %s:%ix%i square:%ix%i', s, text.text, text.contentWidth, text.contentHeight, w, h))
	--print(string.format("fill(%s) size:%f is scale %f", text.text, text.size, text.xScale))
	return text.xScale
end

--[[local function isPointInsideRectangle(rectangle, x, y)
        local c = math.cos(-rectangle.rotation*math.pi/180)
        local s = math.sin(-rectangle.rotation*math.pi/180)
        
        -- UNrotate the point depending on the rotation of the rectangle
        local rotatedX = rectangle.x + c * (x - rectangle.x) - s * (y - rectangle.y)
        local rotatedY = rectangle.y + s * (x - rectangle.x) + c * (y - rectangle.y)
        
        -- perform a normal check if the new point is inside the 
        -- bounds of the UNrotated rectangle
        local leftX = rectangle.x - rectangle.width / 2
        local rightX = rectangle.x + rectangle.width / 2
        local topY = rectangle.y - rectangle.height / 2
        local bottomY = rectangle.y + rectangle.height / 2
        
        return leftX <= rotatedX and rotatedX <= rightX and
                topY <= rotatedY and rotatedY <= bottomY
end]]

local tapTimer, tapTransition

local tapStartTime, tapTotalTime, tapStartAlpha, tapDelta, tapEndAlpha, tapEndTime

local function fixTileGroupSegments()
	local myGroup = tileGroup.zoomGroup
	if myGroup.segments then
		for _,v in pairs(myGroup.segments) do
			v.x = v.x + myGroup.x + tileGroup.x
			v.y = v.y + myGroup.y + tileGroup.y
		end
	end
end

local function setTapGroupAlpha(alpha)
	if tileGroup then
		local myGroup = tileGroup.zoomGroup
		if myGroup then
			myGroup.alpha = alpha
			if myGroup.segments then
				for _,v in pairs(myGroup.segments) do v.alpha = alpha end
			end
		end
	end
end

local function tapFader(event)
	local now = event.time
	if now < tapEndTime then
		local newAlpha = easing.linear(now-tapStartTime, tapTotalTime, tapStartAlpha, tapDelta)
		setTapGroupAlpha(newAlpha)
	else
		Runtime:removeEventListener( "enterFrame", tapFader )
		--timer.cancel(tapTransition)
		setTapGroupAlpha(tapEndAlpha)
	end
end

function osmTiles:removeTapGroup(event)
	--print('removeTapGroup('..type(event)..'('..tostring(event)..'))')
	if not event then
		timer.performWithDelay(100, function () osmTiles:removeTapGroup(true) end)
	else
		if tapTimer then timer.cancel(tapTimer) tapTimer=nil end
		if tapTransition then Runtime:removeEventListener( "enterFrame", tapFader ) tapTransition=nil end
		setTapGroupAlpha(0)
	end
end

local function fadeZoomGroup(endAlpha, totalTime)
	if tapTransition then Runtime:removeEventListener( "enterFrame", tapFader ) end
	tapStartTime = MOAISim.getDeviceTime()*1000
	tapTotalTime = totalTime
	tapEndTime = tapStartTime+tapTotalTime
	tapStartAlpha = tileGroup.zoomGroup.alpha
	tapEndAlpha = endAlpha
	tapDelta = tapEndAlpha-tapStartAlpha
	Runtime:addEventListener( "enterFrame", tapFader )
	--tapTransition = timer.performWithDelay( 1000/30, tapFader, 0)
	tapTransition = true
	return tapTransition
end

--[[local function tapTransitionComplete()
	tapTransition = nil
end]]

local function tapTimerExpired()
	--tileGroup.zoomGroup.alpha = 0	-- Make it invisible until tapped again
	--tapTransition = transition.to( tileGroup.zoomGroup, { alpha = 0, time=2000, onComplete = tapTransitionComplete } )
	tapTransition = fadeZoomGroup(0, 2000)
	tapTimer = nil
end

local function resetTapTimer()
	if tapTimer then
		timer.cancel(tapTimer)
	else
		--if tapTransition then transition.cancel(tapTransition); tapTransition = nil end
		--transition.to( tileGroup.zoomGroup, { alpha = 0.75, time=500 } )
--		if tapTransition then timer.cancel(tapTransition); tapTransition = nil end
		fadeZoomGroup(0.75, 250)
		tileGroup:addChild(tileGroup.zoomGroup)
		--tileGroup.zoomGroup.alpha = 0.75	-- Make zoom control visible
	end
	tapTimer = timer.performWithDelay( 5*1000, tapTimerExpired)
end

function osmTiles:validLatLon(lat_deg, lon_deg)	-- returns true or false
	return tilemgr:validLatLon(lat_deg, lon_deg)
end

local function osmTileNum(lat_deg, lon_deg, zoom)	-- lat/lon in degrees gives xTile, yTile
	return tilemgr:osmTileNum(lat_deg, lon_deg, zoom)
end
-- This returns the NW-corner of the square. Use the function with xtile+1 and/or ytile+1
-- to get the other corners. With xtile+0.5 & ytile+0.5 it will return the center of the tile. 
local function osmTileLatLon(xTile, yTile, zTile)	-- xTile, yTile, zoom -> lat, lon
	return tilemgr:osmTileLatLon(xTile, yTile, zTile)
end

function osmTiles:getCenter()
	return tileGroup.lat, tileGroup.lon, zoom
end


local lastEnsureX, lastEnsureY, lastEnsureZ
function osmTiles:ensureTiles(lat, lon)
	local xTile, yTile = osmTileNum(lat, lon, zoom)
	if xTile and yTile then
		xTile, yTile = math.floor(xTile), math.floor(yTile)
		if not lastEnsureX or not lastEnsureY or not lastEnsureZ
		or lastEnsureX ~= xTile or lastEnsureY ~= yTile or lastEnsureZ ~= zoom then
			if not lastEnsureX then print("not lastEnsureX("..tostring(lastEnsureX)..")") end
			if not lastEnsureY then print("not lastEnsureY("..tostring(lastEnsureY)..")") end
			if not lastEnsureZ then print("not lastEnsureZ("..tostring(lastEnsureZ)..")") end
			if lastEnsureX and lastEnsureY and lastEnsureZ then
				if lastEnsureX ~= xTile then print("lastEnsureX("..tostring(lastEnsureX)..") ~= "..tostring(xTile)) end
				if lastEnsureY ~= yTile then print("lastEnsureY("..tostring(lastEnsureY)..") ~= "..tostring(yTile)) end
				if lastEnsureZ ~= zoom then print("lastEnsureZ("..tostring(lastEnsureZ)..") ~= "..tostring(zoom)) end
			end
			print(string.format("ensureTiles:last: %s/%s/%s vs %d/%d/%d",
					tostring(lastEnsureZ), tostring(lastEnsureX), tostring(lastEnsureY),
					zoom, xTile, yTile))
			
			tilemgr:osmCheckTiles(xTile,yTile,zoom,function(x,y,z,status)
											print(string.format("ensureTiles:%d/%d/%d %s from %s/%s/%s",
																z,x,y,tostring(status),
																tostring(lastEnsureZ), tostring(lastEnsureX), tostring(lastEnsureY)))
											if status == "OK" then
												lastEnsureX, lastEnsureY, lastEnsureZ = x, y, z
											end
										end)
		else
--			print(string.format("ensureTiles:last: %s/%s/%s matched %d/%d/%d matched!",
--					tostring(lastEnsureZ), tostring(lastEnsureX), tostring(lastEnsureY),
--					zoom, xTile, yTile))
		end
	end
end

function osmTiles:moveTo(lat, lon, newZoom, noCrossHairs)
	local force = false
	if not lat or not lon then
		force = true
		lat = tileGroup.lat
		lon = tileGroup.lon
		newZoom = zoom
	end
	if serviceActive then
		if simRunning then
			local start = MOAISim.getDeviceTime()
			performWithDelay2("serviceMoveTo",1,function()
								local elapsed = (MOAISim.getDeviceTime()-start)*1000
								--print(string.format("moveTo:finishing service deferral after %.2fms", elapsed))
								self:moveTo(lat,lon,newZoom)
								end)
		end
	else
	newZoom = newZoom or zoom
--print('moveTo:'..lat..' '..lon..' '..tostring(newZoom).." service:"..tostring(serviceActive))
	if force or tileGroup.lat ~= lat or tileGroup.lon ~= lon or zoom ~= newZoom then
local start = MOAISim.getDeviceTime()
		local xTile, yTile = osmTileNum(lat, lon, zoom)
		if xTile and yTile then
			tileGroup.lat, tileGroup.lon = lat, lon
--print(string.format('moveTo:%f %f is Tile %d/%d/%d', lat, lon, zoom, xTile, yTile))
			if zoom == newZoom then
				config.lastMapLat, config.lastMapLon, config.lastMapZoom = lat, lon, newZoom
				osmTiles:osmLoadTiles(xTile, yTile, zoom, force)
				invokeCallbacks('move')
			else
				osmTiles:zoomTo(newZoom, noCrossHairs)
			end
		end
local elapsed = (MOAISim.getDeviceTime()-start)*1000
if elapsed > 10 then print("osmTiles:moveTo:Took "..elapsed.."ms") end
	-- else print(string.format('moveTo %.5f %.5f %i redundant', lat, lon, newZoom))
	end
	end
end

function osmTiles:pixelLatLon()
	local xTile, yTile = osmTileNum(tileGroup.lat, tileGroup.lon, zoom)
	--xTile, yTile = math.floor(xTile), math.floor(yTile)	-- Ensures room to add 0.5!
	local latNW, lonNW = osmTileLatLon(xTile-0.25, yTile-0.25, zoom)
	local latCenter, lonCenter = osmTileLatLon(xTile+0.25, yTile+0.25, zoom)
	local latPerY = (latCenter-latNW)/(tileSize/2)
	local lonPerX = (lonCenter-lonNW)/(tileSize/2)
	return latPerY, lonPerX
end

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

function osmTiles:deltaMove(dx, dy)	-- in pixels
	local start = MOAISim.getDeviceTime()
--	local xTile, yTile = osmTileNum(tileGroup.lat, tileGroup.lon, zoom)
--	xTile, yTile = math.floor(xTile), math.floor(yTile)	-- Ensures room to add 0.5!
--	local latNW, lonNW = osmTileLatLon(xTile, yTile, zoom)
--	local latCenter, lonCenter = osmTileLatLon(xTile+0.5, yTile+0.5, zoom)
--	local latPerY = (latCenter-latNW)/128
--	local lonPerX = (lonCenter-lonNW)/128

	local latPerY, lonPerX = osmTiles:pixelLatLon()
	local newLat = tileGroup.lat-dy*latPerY
	local newLon = tileGroup.lon-dx*lonPerX
	if newLat < -85.0511 then newLat = -85.0511+latPerY*(tileSize/2) end
	if newLat > 85.0511 then newLat = 85.0511-latPerY*(tileSize/2) end
	if newLon < -180 then newLon = newLon + 360 end
	if newLon > 180 then newLon = newLon - 360 end
	osmTiles:moveTo(newLat, newLon)
local elapsed = (MOAISim.getDeviceTime()-start)*1000
if elapsed > 10 then print("osmTiles:deltaMove:Took "..elapsed.."ms") end
	
	osmTiles:showCrosshair()
end

function osmTiles:crosshairActive()
	return tileGroup.crossHair ~= nil
end

function osmTiles:removeCrosshair()
	if tileGroup.crossTimer then tileGroup.crossTimer:stop() end
	if tileGroup.crossHair then
		tileGroup:removeChild(tileGroup.crossHair)
		tileGroup.crossHair = nil
	end
end

function osmTiles:showCrosshair()
	if not tileGroup.crossHair then
		local w, h = tileGroup.width, tileGroup.height
		local cx, cy = w/2, h/2
		local len = math.min(cx,cy)/4
		local len2 = len*2
		local vertPoints = { len,len-len2, len,len+len2 }
		local horzPoints = { len-len2,len, len+len2,len }

		tileGroup.crossHair = Graphics { left=cx-len, top=cy-len, width=len*2, height=len*2 }
		tileGroup.crossHair:setPenColor(0,0,0,0.75):setPenWidth(math.max(config.Screen.scale*(tileGroup.crossWidth or 2),1))
		tileGroup.crossHair:drawLine(vertPoints):drawLine(horzPoints)
--[[
		if not tileGroup.crossWidth then
			tileGroup.crossWidth = 1
		else
			tileGroup.crossWidth = tileGroup.crossWidth * 2
			if tileGroup.crossWidth > 64 then
				tileGroup.crossWidth = 1
			end
		end
		local width = math.max(config.Screen.scale*tileGroup.crossWidth,1)
		tileGroup.crossHair:fillRect(len-width,len-len2, len+width, len+len2)
		tileGroup.crossHair:fillRect(len-len2,len-width, len+len2, len+width)
]]
		tileGroup.crossHair:setPriority(3000000)
		tileGroup:addChild(tileGroup.crossHair)
	end
	if tileGroup.crossTimer then tileGroup.crossTimer:stop() end
	tileGroup.crossTimer = performWithDelay(5000,
						function()
							tileGroup.crossTimer = nil	-- It expired
							osmTiles:removeCrosshair()
						end)
end

local function showSliderText(slider, value)
if slider then
	if not slider.text then
		local text = display.newEmbossedText(value, 0,0, native.systemFont, math.min(slider.contentWidth,slider.contentHeight)) --display.newText(value, 0,0, native.systemFont, 128)
		tileGroup:addChild(text)
--myText:setText( "Hello World!" )
		text:setTextColor( 64, 64, 64 )
		text:setEmbossColor({highlight={r=128,g=128,b=128,a=255}, shadow={r=0,g=0,b=0,a=255}})
		--text:setEmbossColor({highlight={r=64,g=64,b=64,a=255}, shadow={r=64,g=64,b=64,a=255}})
		if not slider.textScale then
			slider.textScale = fillTextSquare(slider, text)
		--else text.size = slider.textSize
		end
		slider.text = text
	end
	if value then slider.text:setText(value) end
	slider.text.x = slider.x
	slider.text.y = slider.y
--[[	local function textTimeout()
		slider.text:removeSelf()
		slider.transition = nil
		slider.text = nil
		text = nil
	end
	if slider.transition then
		transition.cancel(slider.transition)
		slider.transition = nil
	end]]
--[[	if slider.text then
		slider.text:removeSelf()
		slider.text = nil
	end]]
	--slider.transition = transition.to( zoomText, { alpha = 0, time=1000, transition = easing.inQuad, onComplete = textTimeout } )
end
end

local function showZoom(newZoom)
	newZoom = newZoom or zoom
	showSliderText(tileGroup.zoomGroup.zoomSlider, string.format("%2i", newZoom))
end

function osmTiles:deltaZoom(delta)
	local newZoom = zoom + delta
	return osmTiles:zoomTo(newZoom)
end

local zoomToast

function osmTiles:zoomTo(newZoom, noCrossHairs)
	if newZoom < 0 then newZoom = 0 elseif newZoom > zoomMax then newZoom = zoomMax end
	newZoom = math.floor(newZoom)
	if newZoom ~= zoom then
local start = MOAISim.getDeviceTime()
		--print (string.format('Zooming to %f', newZoom))
		--tileGroup.zoomGroup.alpha = 0	-- Make it invisible to prevent additional taps
		local lat, lon = tileGroup.lat, tileGroup.lon
		local xTile, yTile = osmTileNum(lat, lon, newZoom)
		if xTile and yTile then
			if zoomToast then toast.destroy(zoomToast, true) end
			zoomToast = toast.new("Zoom:"..newZoom, 500, nil, function() zoomToast = nil end)
			zoom = newZoom
			zoomDiv = 1/(2^(20-zoom))*tileSize	-- for symbol and track fixing
			zoomDelta = 2^zoom*tileSize	-- pixels across world wrapping
--print('zoomTo:'..lat..' '..lon..' '..newZoom)
			config.lastMapZoom = newZoom
			showZoom(zoom)
			if tileGroup.zoomGroup.zoomSlider then
				tileGroup.zoomGroup.zoomSlider:setValue(math.floor(zoom/zoomMax*100+0.5))
			end
			--print(string.format('zoomTo:%f %f is Tile %i/%i/%i', lat, lon, zoom, xTile, yTile))
			osmTiles:osmLoadTiles(xTile, yTile, zoom);
			invokeCallbacks('zoom')
		end
		if not noCrossHairs then osmTiles:showCrosshair() end
print("osmTiles:zoomTo:Took "..((MOAISim.getDeviceTime()-start)*1000).."ms")
	end
	return newZoom
end
local function zoomSliderListener( event )
	local slider = event.target
	local value = event.value
	-- print( "ZoomSlider at " .. value .. "%" )
	osmTiles:zoomTo(math.floor(value/100*zoomMax+0.5))
	resetTapTimer()
end

local function showAlpha(newAlpha)
	newAlpha = newAlpha or tileAlpha
	showSliderText(tileGroup.zoomGroup.alphaSlider, string.format("%i%%", newAlpha*100))
end

function osmTiles:deltaTileAlpha(delta)
	osmTiles:setTileAlpha(tileAlpha+delta)
end

function osmTiles:setTileAlpha(newAlpha)
--print("setTileAlpha to ", newAlpha)
	if newAlpha < 0 then newAlpha = 0
	elseif newAlpha > 1 then newAlpha = 1
	end
	if newAlpha ~= tileAlpha then
		tileAlpha = newAlpha
	toast.new(tostring(math.floor(tileAlpha*100)).."% Opaque", 1000)
		tileGroup.tilesGroup.alpha = tileAlpha		-- change the actual map alpha
		tileGroup.tilesGroup:setColor(tileAlpha,tileAlpha,tileAlpha,tileAlpha)
		config.lastMapAlpha = tileAlpha
	end
end

local function alphaSliderListener( event )
	local slider = event.target
	local value = event.value
	--print( "AlphaSlider at " .. value .. "%" )
	osmTiles:setTileAlpha(value/100)
	resetTapTimer()
end

local scaleToast

function osmTiles:setTileScale(newScale)
	if newScale < 1 then newScale = 1 elseif newScale > 9 then newScale = 9 end
	newScale = math.floor(newScale)
	if newScale ~= tileScale then
local start = MOAISim.getDeviceTime()
			if scaleToast then toast.destroy(scaleToast, true) end
			scaleToast = toast.new("Scale:"..newScale, 500, nil, function() scaleToast = nil end)
			tileScale = newScale
			tileSize = 256*tileScale
			config.lastMapScale = tileScale
			zoomDiv = 1/(2^(20-zoom))*tileSize	-- for symbol and track fixing
			zoomDelta = 2^zoom*tileSize	-- pixels across world wrapping
			osmTiles:resetSize('scale')
		osmTiles:showCrosshair()
print("osmTiles:zoomTo:Took "..((MOAISim.getDeviceTime()-start)*1000).."ms")
	end
	return newZoom
end


local function tileTap( event )
	resetTapTimer()
	--print ('tileTap:'..event.name..':'..event.numTaps..' @ '..event.x..','..event.y)
	
	if tapTimer or tapTransition then	-- if the slider is visible
		--resetTapTimer()
		if event.numTaps > 1 then
local function getSliderPercent(slider)
	local localx, localy = event.target:contentToLocal(event.x, event.y)
	local width = slider.contentWidth
	local height = slider.contentHeight
	--print('AlphaBar:tap '..localx..','..localy..' slider@'..slider.x..','..slider.y..' size '..width..'x'..height)
	localx = localx - (slider.x-width/2)
	localy = localy - (slider.y-height/2)
	if localx >= 0 and localx <= width and localy >= 0 and localy <= height then	-- inside slider?
		local xPercent = localx/width
		local yPercent = 1.0-(localy/height)
		--print (string.format('slider:x:%i%% y:%i%% width:%i height%i', xPercent*100, yPercent*100, width, height))
		if width > height then
			return xPercent
		else
			return yPercent
		end
	else
		--print(string.format("slider@%f,%f out of range in size %fx%f", localx, localy, width, height))
	end
	return nil
end

local function checkSliderTap(slider, listener)
	local Percent = getSliderPercent(slider)
	if Percent then
		local percent = math.floor(100*Percent+0.5)
		slider:setValue(percent)
		listener({ target=slider, value=percent})
		return true
	end
	return false
end
			if checkSliderTap(tileGroup.zoomGroup.alphaSlider, alphaSliderListener) then return true end
			if checkSliderTap(tileGroup.zoomGroup.zoomSlider, zoomSliderListener) then return true end
		end
	end
    return false
end 














local function calculateDelta( previousTouches, event )
	local id,touch = next( previousTouches )
	if event.id == id then
		id,touch = next( previousTouches, id )
		assert( id ~= event.id )
	end

	local dx = touch.x - event.x
	local dy = touch.y - event.y
	return dx, dy
end

--local debugText = nil
local stretchImage = nil
local ln2 = math.log(2)

local function log2(n)
	return math.log(n) / ln2
end

-- create a table listener object for the bkgd image
local function tileTouch( event )

	local self = tileGroup	-- Temporary!  (yeah, right!)
	
	local result = true

	local phase = event.phase
	--print('tileTouch: phase:'..phase..' @ '..event.x..','..event.y)

	local previousTouches = self.previousTouches

	local numTotalTouches = 1
	if ( previousTouches ) then
		-- add in total from previousTouches, subtract one if event is already in the array
		numTotalTouches = numTotalTouches + self.numPreviousTouches
		if previousTouches[event.id] then
			numTotalTouches = numTotalTouches - 1
		end
	end

	if "began" == phase then
		-- Very first "began" event
		if ( not self.isFocus ) then
			-- Subsequent touch events will target button even if they are outside the contentBounds of button
			display.getCurrentStage():setFocus( self )
			self.isFocus = true

			previousTouches = {}
			self.previousTouches = previousTouches
			self.numPreviousTouches = 0

-- This returns the NW-corner of the square. Use the function with xtile+1 and/or ytile+1
-- to get the other corners. With xtile+0.5 & ytile+0.5 it will return the center of the tile. 
--local function osmTileNum(lat_deg, lon_deg, zoom)	-- lat/lon in degrees gives xTile, yTile
--local function osmTileLatLon(xTile, yTile, zTile)	-- xTile, yTile, zoom -> lat, lon
--????? tileGroup.lat, tileGroup.lon = lat, lon
local xTile, yTile = osmTileNum(tileGroup.lat, tileGroup.lon, zoom)
xTile, yTile = math.floor(xTile), math.floor(yTile)
local latNW, lonNW = osmTileLatLon(xTile, yTile, zoom)
local latCenter, lonCenter = osmTileLatLon(xTile+0.5, yTile+0.5, zoom)
--print(string.format('%.4f lat/pixel(y) %.4f lon/pixel(x)', (latCenter-latNW)/128, (lonCenter-lonNW)/128))
self.touchX = event.x
self.touchY = event.y
self.latPerY = (latCenter-latNW)/(tileSize/2)
self.lonPerX = (lonCenter-lonNW)/(tileSize/2)

		elseif ( not self.distance ) then
			local dx,dy

			if previousTouches and ( numTotalTouches ) >= 2 then
				dx,dy = calculateDelta( previousTouches, event )
			end

			-- initialize to distance between two touches
			if ( dx and dy ) then
				local d = math.sqrt( dx*dx + dy*dy )
				if ( d > 0 ) then
--[[if not debugText then
debugText = display.newText("", 0,0, native.systemFont, 28)
debugText:setReferencePoint(display.CenterLeftReferencePoint)
debugText.x = display.screenOriginX
debugText.y = display.contentHeight /4
debugText:setTextColor(0,0,0)
end]]
if not stretchImage then
stretchImage = display.capture(tileGroup)
--stretchImage:setReferencePoint(display.TopLeftReferencePoint)
stretchImage.x = stretchImage.x + display.screenOriginX
stretchImage.y = stretchImage.y + display.screenOriginY
end
					self.distance = d
					self.xScaleOriginal = self.xScale
					self.yScaleOriginal = self.yScale
					self.xScaleOriginal = stretchImage.xScale
					self.yScaleOriginal = stretchImage.yScale
					self.originalZoom = zoom
--debugText.text = string.format("d=%.2f", self.distance)
					--print( "distance = " .. self.distance )
				end
			end
		end

		if not previousTouches[event.id] then
			self.numPreviousTouches = self.numPreviousTouches + 1
		end
		previousTouches[event.id] = event

	elseif self.isFocus then
		if "moved" == phase then
			if ( self.distance ) then
				local dx,dy
				if previousTouches and ( numTotalTouches ) >= 2 then
					dx,dy = calculateDelta( previousTouches, event )
				end

				if ( dx and dy ) then
					local newDistance = math.sqrt( dx*dx + dy*dy )
					local scale = newDistance / self.distance
					--resetTapTimer()	-- Make the zoom control visible
					local scale2 = 2^math.modf(log2(scale))
					--print( "newDistance(" ..newDistance .. ") / distance(" .. self.distance .. ") = scale("..  scale ..")" )
--debugText.text = string.format("%.2f -> %.2f -> %i", log2(scale), scale2, self.originalZoom+log2(scale)*2+0.5)
					if ( scale > 0 ) then
						self.newZoom = self.originalZoom + log2(scale2)
						stretchImage.xScale = self.xScaleOriginal * scale2
						stretchImage.yScale = self.yScaleOriginal * scale2
--						self.xScale = self.xScaleOriginal * scale
--						self.yScale = self.yScaleOriginal * scale
					end
				end
			else
				if self.touchX and self.touchY and zoom ~= 0 then
					local dx, dy = event.x - self.touchX, event.y - self.touchY
					--print(string.format('Moved %i x %i', dx, dy))
					--if math.abs(dx) > 10 or math.abs(dy) > 10 then
-- This returns the NW-corner of the square. Use the function with xtile+1 and/or ytile+1
-- to get the other corners. With xtile+0.5 & ytile+0.5 it will return the center of the tile. 
--local function osmTileLatLon(xTile, yTile, zTile)	-- xTile, yTile, zoom -> lat, lon
--????? tileGroup.lat, tileGroup.lon = lat, lon
--stretchImage.latPerY = (latCenter-latNW)/128
--stretchImage.lonPerX = (lonCenter-lonNW)/128
						local newLat = tileGroup.lat-dy*self.latPerY
						local newLon = tileGroup.lon-dx*self.lonPerX
						if newLat < -85.0511 then newLat = -85.0511+self.latPerY*(tileSize/2) end
						if newLat > 85.0511 then newLat = 85.0511-self.latPerY*(tileSize/2) end
						if newLon < -180 then newLon = newLon + 360 end
						if newLon > 180 then newLon = newLon - 360 end
						osmTiles:moveTo(newLat, newLon)
						--stretchImage.x = stretchImage.x + dx
						--stretchImage.y = stretchImage.y + dy
						self.touchX = event.x
						self.touchY = event.y
					--end
				end
			end

			if not previousTouches[event.id] then
				self.numPreviousTouches = self.numPreviousTouches + 1
			end
			previousTouches[event.id] = event

		elseif "ended" == phase or "cancelled" == phase then
			if previousTouches[event.id] then
				self.numPreviousTouches = self.numPreviousTouches - 1
				previousTouches[event.id] = nil
			end

			if ( #previousTouches > 0 ) then
				-- must be at least 2 touches remaining to pinch/zoom
				self.distance = nil
			else
				-- previousTouches is empty so no more fingers are touching the screen
				-- Allow touch events to be sent normally to the objects they "hit"
				display.getCurrentStage():setFocus( nil )

				self.isFocus = false
				self.distance = nil
				self.xScaleOriginal = nil
				self.yScaleOriginal = nil
				if stretchImage then
					stretchImage:removeSelf()
					stretchImage = nil
				end
				if self.newZoom and self.newZoom ~= self.originalZoom then
					osmTiles:zoomTo(self.newZoom)
				end
				self.originalZoom = nil
				self.newZoom = nil
				--[[if debuggingText then
					debugText:removeSelf()
					debugText = nil
				end]]

				-- reset array
				self.previousTouches = nil
				self.numPreviousTouches = nil
			end
		end
	end

	return result
end





local function displayFailed(n,what,size,color)
	if n >= 1 and n <= #tileGroup.tiles then
		what = what or "\nFAIL"
		tileGroup.tiles[n]:removeChildAt(1)
		if tileGroup.tiles[n]:getChildAt(1) or tileGroup.tiles[n]:getNumChildren() > 0 then
			print('displayFailed['..n..'] '..tileGroup.tiles[n]:getNumChildren()..' ORPHAN!  from '..tileGroup.tiles[n].from)
		end

		local image = TextLabel { text=what, textSize=size or 62 }
		image:fitSize()
		if type(color) == 'table' and #color == 4 then
			image:setColor(unpack(color))
		else image:setColor( 1.0,0.0,0.0,1.0)
		end
		image:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
		image:setRect(-(tileSize/2), -(tileSize/2), (tileSize/2), (tileSize/2))
		--image:setColor( 0.5,0.5,0.5,0.5 )
	--	image:setLoc(tileSize/2,tileSize/2);
		image:setLoc(tileSize/2/tileScale, tileSize/2)
		tileGroup.tiles[n]:addChild(image)
		if tileGroup.tiles[n]:getNumChildren() > 1 then
			print('displayFailed['..n..'] '..tileGroup.tiles[n]:getNumChildren()..' EXTRA!  from '..tileGroup.tiles[n].from)
		end
		tileGroup.tiles[n].from = 'displayFailed'
		--tileGroup.tile = image
if debugging then print(string.format("displayFailed:[%d]<-%d,%d,%d", n, -1,-1,-1)) end
		tileGroup.tiles[n].xTile, tileGroup.tiles[n].yTile, tileGroup.tiles[n].zTile = -1, -1, -1

		--if tapTimer then tileGroup.zoomGroup.alpha = 0.75 end	-- Allow zooming again
		--tileGroup.tiles[n][1].alpha = tileAlpha
	end
end





local incognita = { "\nTerra\nIncognita",
						"\nHere be\ndragons", 
						"\nHere are\ndragons",
						"\nHIC SVNT\nDRACONES",
						"\nHIC SVNT\nLEONES",
						"\nHere are\nlions",
						"\nNothing\nto see\nhere",
						"\n\nGray" }

local function displayGrayTile(n, temp)
	if n >= 1 and n <= #tileGroup.tiles then
		if not temp then
			displayFailed(n,incognita[math.random(#incognita)], 42, {0.5,0.5,0.5,1.0} )
		else
			tileGroup.tiles[n]:removeChildAt(1)
			if tileGroup.tiles[n]:getChildAt(1) or tileGroup.tiles[n]:getNumChildren() > 0 then
				print('displayGrayTile['..n..'] '..tileGroup.tiles[n]:getNumChildren()..' ORPHAN!  from '..tileGroup.tiles[n].from)
			end
			--print("GrayTile["..n.."]")
			local image = display.newRect(0,0,tileSize,tileSize)
			image:setFillColor(128,128,128)
	--		image.x = tileSize/2
	--		image.y = tileSize/2
			image.x, image.y = tileSize/2/tileScale, tileSize/2
			tileGroup.tiles[n]:addChild(image)
			if tileGroup.tiles[n]:getNumChildren() > 1 then
				print('displayGrayTile['..n..'] '..tileGroup.tiles[n]:getNumChildren()..' EXTRA!  from '..tileGroup.tiles[n].from)
			end
			tileGroup.tiles[n].from = 'displayGrayTile'
			if not temp then
				tileGroup.tiles[n].xTile, tileGroup.tiles[n].yTile, tileGroup.tiles[n].zTile = -1, -1, -1
if debugging then print(string.format("displayGrayTile:[%d]<-%d,%d,%d", n, -1,-1,-1)) end
			end
		end
	end
end

local bit = bit
if type(bit) ~= 'table' then
	if type(bit32) == 'table' then
		print('otp:using internal bit32 module')
		bit = bit32
	else
		print('otp:using mybits type(bit)='..type(bit))
		bit = require("mybits")
		bit.lshift = bit.blshift
		bit.rshift = bit.blogic_rshift
	end
else print('otp:using internal bit module!')
end


-- http://ldeffenb.dnsalias.net:14171/hot/17/35929/54878.png
--[[
local function getZoomImage(x,y,z)
		local tstart = MOAISim.getDeviceTime()
	if z > 0 then
		local szoom, sx, sy = z, x, y
		local stretch = 0
		repeat
			szoom = szoom - 1
			stretch = stretch + 1
			sx = math.floor(sx/2) sy = math.floor(sy/2)
			local source = tilemgr:osmGetTileImage(0,sx,sy,szoom)
			if source then
				local pow2 = bit.lshift(1,stretch)
				local size = 256 / pow2
				local xoffset = (x%pow2)*size
				local yoffset = (y%pow2)*size
				local image

local saveImages = false

				if saveImages then
					source:write(string.format("%d-%d.%d.%d.Source(%d.%d).png", szoom, z, x, y, sx, sy))
					local source2
					if MOAIImageTexture and type(MOAIImageTexture.new) == "function" then
						source2 = MOAIImageTexture.new()
					else source2 = MOAIImage.new()
					end
					if type(source.getFormat) == "function" then
						--print("getZoomImage:Source Format:"..tostring(source:getFormat()))
						source2:init(256,256,source:getFormat())
					else source2:init(256,256)
					end
					source2:copyRect(source, 0, 0, 256, 256, 0, 0, 256, 256)
					source2:write(string.format("%d-%d.%d.%d.Source2(%d.%d).png", szoom, z, x, y, sx, sy))
				end

				if MOAIImageTexture and type(MOAIImageTexture.new) == "function" then
					image = MOAIImageTexture.new()
				else image = MOAIImage.new()
				end
				if type(image.setDebugName) == "function" then
					image:setDebugName(string.format("zoom %d %d %d",sx,sy,szoom))
				end

				if type(source.getFormat) == "function" then
					--print("getZoomImage:Source Format:"..tostring(source:getFormat()))
					image:init(size,size,source:getFormat())
				else image:init(size,size)
				end
				local tstart2 = MOAISim.getDeviceTime()
				image:copyRect(source, xoffset, yoffset, xoffset+size, yoffset+size,
								0, 0, size, size, MOAIImage.FILTER_LINEAR)	-- MOAIImage.FILTER_LINEAR (default), MOAIImage.FILTER_NEAREST
				local telapsed2 = (MOAISim.getDeviceTime()-tstart2)*1000
								
				if saveImages then
					image:write(string.format("%d-%d.%d.%d.Dest(%d.%d).png", szoom, z, x, y, xoffset, yoffset))
				end
								
				--print(string.format("getZoomImage:Stretching %d %d->%d Offset:%d %d size %d", stretch, szoom, z, xoffset, yoffset, size))

				local telapsed = (MOAISim.getDeviceTime()-tstart)*1000
				--print(string.format("getZoomImage:got %d %d %d<-%d in %dmsec (%d in copyRect)", x, y, z, szoom, telapsed, telapsed2))
				return Sprite { texture = image, left = 0, top = 0, width=256, height=256 }, szoom
			end
		until szoom <= 0 or stretch > 5
	end
	local telapsed = (MOAISim.getDeviceTime()-tstart)*1000
	--print(string.format("getZoomImage:FAILED %d %d %d in %dmsec", x, y, z, telapsed))
	return nil
end
]]

local function getZoomImage(x,y,z)
		local tstart = MOAISim.getDeviceTime()
	if z > 0 then
		local szoom, sx, sy = z, x, y
		local stretch = 0
		repeat
			szoom = szoom - 1
			stretch = stretch + 1
			sx = math.floor(sx/2) sy = math.floor(sy/2)
			local source = tilemgr:osmGetTileTexture(0,sx,sy,szoom,true)
			if source then
				local pow2 = bit.lshift(1,stretch)
				local size = 256 / pow2
				local xoffset = (x%pow2)*size
				local yoffset = (y%pow2)*size

				local image = MapSprite { texture=source }
				image:setMapSize(pow2, pow2, size, size)
				image:setMapSheets(size, size, pow2, pow2)
				image:setTile(1,1,(y%pow2)*pow2+(x%pow2)+1)
				image:setScl(pow2,pow2)
				return image, szoom

			end
		until szoom <= 0 or stretch > 5
	end
	local telapsed = (MOAISim.getDeviceTime()-tstart)*1000
	--print(string.format("getZoomImage:FAILED %d %d %d in %dmsec", x, y, z, telapsed))
	return nil
end



local function displayBusyTile(n, x, y, z)
	if n >= 1 and n <= #tileGroup.tiles then
		tileGroup.tiles[n]:removeChildAt(1)
		if tileGroup.tiles[n]:getChildAt(1) or tileGroup.tiles[n]:getNumChildren() > 0 then
			print('displayBusyTile['..n..'] '..tileGroup.tiles[n]:getNumChildren()..' ORPHAN!  from '..tileGroup.tiles[n].from)
		end
		
		--print("BusyTile["..n.."]")
		local group = Group({left=1,top=1})	-- Need non-zero Left/Top to work
		group:setPos(0,0)	-- Don't ask me why it can't be initialized in Group()

	--[[
		local spinner = widget.newSpinner( {left=0, top=0})
		spinner.x = 256/2
		spinner.y = 256/2
		spinner:start()
		group:addChild(spinner)
	]]
	--[[
		displayFailed(n,"*BUSY*")	-- Temporary Spinner replacement
		tileGroup.tiles[n].xTile, tileGroup.tiles[n].yTile, tileGroup.tiles[n].zTile = x, y, z
		local busyText = tileGroup.tiles[n]:getChildAt(1)
		tileGroup.tiles[n]:removeChild(busyText)
		group:addChild(busyText)
	]]

		local zoomImage, szoom
		zoomImage, szoom = getZoomImage(x,y,z)
		if zoomImage then
			group:addChild(zoomImage)
			local text = TextLabel { text = string.format("%d->%d\n%d\n%d", szoom, z,x,y), textSize=62 }
			text:fitSize()
			text:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
			text:setRect(-tileSize/2, -tileSize/2, tileSize/2, tileSize/2)
			text:setColor( 0.5,0.5,0.5,0.25)
			--text:setLoc(256-text:getWidth()/2, 256/2)
		--	text:setLoc(tileSize/2, tileSize/2)
			text:setLoc(tileSize/2/tileScale, tileSize/2)
			group:addChild(text)
		else
			local text = TextLabel { text = tostring(z)..'\n'..tostring(x)..'\n'..tostring(y), textSize=62 }
			text:fitSize()
			text:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
			text:setRect(-tileSize/2, -tileSize/2, tileSize/2, tileSize/2)
			text:setColor( 0.5,0.5,0.5,1.0)
			--text:setLoc(256-text:getWidth()/2, 256/2)
		--	text:setLoc(tileSize/2, tileSize/2)
			text:setLoc(tileSize/2/tileScale, tileSize/2)
			group:addChild(text)
		end

		tileGroup.tiles[n]:addChild(group)

		if tileGroup.tiles[n]:getNumChildren() > 1 then
			print('displayBusyTile['..n..'] '..tileGroup.tiles[n]:getNumChildren()..' EXTRA!  from '..tileGroup.tiles[n].from)
		end
		tileGroup.tiles[n].from = 'displayBusyTile'
	end
end

local function displayTileFailed(n,x,y,z)
	if n >= 1 and n <= #tileGroup.tiles then
		tileGroup.tiles[n]:removeChildAt(1)
		if tileGroup.tiles[n]:getChildAt(1) or tileGroup.tiles[n]:getNumChildren() > 0 then
			print('displayTileFailed['..n..'] '..tileGroup.tiles[n]:getNumChildren()..' ORPHAN!  from '..tileGroup.tiles[n].from)
		end

		--print("tileFailed["..n.."]")
		local group = Group({left=1,top=1})	-- Need non-zero Left/Top to work
		group:setPos(0,0)	-- Don't ask me why it can't be initialized in Group()

		local zoomImage, szoom
		zoomImage, szoom = getZoomImage(x,y,z)
		if zoomImage then
			group:addChild(zoomImage)
			local text = TextLabel { text = string.format("%d->%d\nFAIL", szoom, z), textSize=62 }
			text:fitSize()
			text:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
			text:setRect(-tileSize/2, -tileSize/2, tileSize/2, tileSize/2)
			text:setColor( 0.5,0.0,0.0,0.25)
			--text:setLoc(256-text:getWidth()/2, 256/2)
		--	text:setLoc(tileSize/2, tileSize/2)
			text:setLoc(tileSize/2/tileScale, tileSize/2)
			group:addChild(text)
		else
			local text = TextLabel { text = tostring(z)..'\n'..tostring(x)..'\n'..tostring(y), textSize=62 }
			text:fitSize()
			text:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
			text:setRect(-tileSize/2, -tileSize/2, tileSize/2, tileSize/2)
			text:setColor( 1.0,0.0,0.0,1.0)
			--text:setLoc(256-text:getWidth()/2, 256/2)
		--	text:setLoc(tileSize/2, tileSize/2)
			text:setLoc(tileSize/2/tileScale, tileSize/2)
			group:addChild(text)
		end

		tileGroup.tiles[n]:addChild(group)

		if tileGroup.tiles[n]:getNumChildren() > 1 then
			print('displayTileFailed['..n..'] '..tileGroup.tiles[n]:getNumChildren()..' EXTRA!  from '..tileGroup.tiles[n].from)
		end
		tileGroup.tiles[n].from = 'displayTileFailed'

--[[
		local image = TextLabel { text=what, textSize=size or 62 }
		image:fitSize()
		if type(color) == 'table' and #color == 4 then
			image:setColor(unpack(color))
		else image:setColor( 1.0,0.0,0.0,1.0)
		end
		image:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
		image:setRect(-(tileSize/2), -(tileSize/2), (tileSize/2), (tileSize/2))
		--image:setColor( 0.5,0.5,0.5,0.5 )
	--	image:setLoc(tileSize/2,tileSize/2);
		image:setLoc(tileSize/2/tileScale, tileSize/2)
		tileGroup.tiles[n]:addChild(image)
		if tileGroup.tiles[n]:getNumChildren() > 1 then
			print('displayTileFailed['..n..'] '..tileGroup.tiles[n]:getNumChildren()..' EXTRA!  from '..tileGroup.tiles[n].from)
		end
		tileGroup.tiles[n].from = 'displayTileFailed'
		--tileGroup.tile = image
if debugging then print(string.format("displayTileFailed:[%d]<-%d,%d,%d", n, -1,-1,-1)) end
		tileGroup.tiles[n].xTile, tileGroup.tiles[n].yTile, tileGroup.tiles[n].zTile = -1, -1, -1

		--if tapTimer then tileGroup.zoomGroup.alpha = 0.75 end	-- Allow zooming again
		--tileGroup.tiles[n][1].alpha = tileAlpha
]]
	end
end




--local offscreenSymbols = display.newGroup()
--offscreenSymbols.alpha = 0
--local deletedSymbols = display.newGroup()
--deletedSymbols.alpha = 0

local allSymbols = {}
local activeTracks = {}
local trackGroup = Group()
tileGroup:addChild(trackGroup)

local activePolys = {}
local polyGroup = Group()
tileGroup:addChild(polyGroup)

local symbolGroup = Group()
symbolGroup.groupCount = 0
tileGroup:addChild(symbolGroup)

local labelGroup = Group()
local labelAlpha = 1.0 -- 0.7 -- 0.8
labelGroup:setColor(labelAlpha,labelAlpha,labelAlpha,labelAlpha)
tileGroup:addChild(labelGroup)
labelGroup.visible = true

function osmTiles:getGroupCounts()
	return symbolGroup:getNumChildren(), labelGroup:getNumChildren(), trackGroup:getNumChildren(), polyGroup:getNumChildren()
end

function osmTiles:showLabels(onOff)
	if type(onOff) == 'nil' then onOff = true end
	labelGroup.visible = onOff
	if labelGroup.visible then
		if symbolGroup.groupCount < MaxSymbols / 2 then
			tileGroup:addChild(labelGroup)
		end
	else tileGroup:removeChild(labelGroup)
	end
end

local function wrapX(x, xo)
	if tileGroup.wrapped and xo then
		local tile = tileGroup.tiles[1]	-- First tile is at center
		local dx = x+xo-tile.x-(tileSize/2)
		local zd = zoomDelta	-- Pixels to the "other side"
		local mabs = math.abs
		if dx < 0 then
			local tx = dx + zd
			if mabs(tx) < mabs(dx) then x = x+zd end
		else
			local tx = dx - zd
			if mabs(tx) < mabs(dx) then x = x-zd end
		end
	end
	return x
end

local function clearTrack(track)
	if track.lineBackground then
		if not trackGroup:removeChild(track.lineBackground) then
			print('Failed to remove trackLineBackground from trackGroup!')
		end
		track.lineBackground:dispose()
		track.lineBackground = nil
	end
	if track.line then
		if not trackGroup:removeChild(track.line) then
			print('Failed to remove trackLine from trackGroup!')
		end
		track.line:dispose()
		track.line = nil
	end
	if track.dots then
		if not trackGroup:removeChild(track.dots) then
			print('Failed to remove trackDots from trackGroup!')
		end
		track.dots:dispose()
		track.dots = nil
	end
	track.points = nil
end

function osmTiles:removeTrack(track)
	if track then
		clearTrack(track)
		if track.activeIndex then
			local index = track.activeIndex
			track.activeIndex = nil	-- make sure it remembers it's gone!
			local lastIndex = #activeTracks
			if index ~= lastIndex then
				activeTracks[index] = activeTracks[lastIndex]
				activeTracks[index].activeIndex = index	-- record the new index
			end
			activeTracks[lastIndex] = nil
		end
	end
end

local function fixupTrack(track, zoomed, stationID)
	stationID = stationID or track.stationID
	track.stationID = stationID
	stationID = stationID or "*unknown*"
	zoomed = zoomed or false
	if track then
		if zoomed
		or ((not track.showDots) and track.dots) then
			--print(stationID..' Clearing track')
			clearTrack(track)
		end
		if not track.points  then
			track.points = {}
		end	-- list of x,y for drawing
		local points = track.points
		local ref = track[#track]
		local lastx, lasty = -1, -1
		local mabs = math.abs
		local lineWidth, dotSize = 4, 7
		local oldest = os.time() - (60*60)	-- Only 1 hour
		for i=#track,1,-1 do
			local p = track[i]
			if p.when < oldest and not track.showDots then break end	-- shorten the tracks to one hour
			if not p.x20 or not p.y20 then
				p.x20, p.y20 = osmTileNum(p.lat, p.lon, 20)
				if p.lat == 0 and p.lon == 0 then
					local text = stationID..":track["..i.."] lat/lon:"..p.lat.."/"..p.lon.." at "..p.x20..","..p.y20
					toast.new(text)
				end
				if not p.x20 or not p.y20 then
					print("osmTiles:fixupTrack:"..stationID.."["..i.."] out of range, lat:"..p.lat.." lon:"..p.lon)
--else print(string.format(",%d,%f,%f", i, p.x20, p.y20))
				end
			end
			p.x, p.y = wrapX(p.x20*zoomDiv,trackGroup.x), p.y20*zoomDiv
			if #points > 0 and mabs(p.x-lastx) > zoomDelta/2 then
				--print(string.format('%s:Truncating screen-crossing track dx:%i > %i @ %i/%i',
				--					tostring(stationID), mabs(p.x-lastx), zoomDelta/2, #track-i, #track))
				break	-- I really want to just split the lines, but not yet!
			end
			if #points == 0 or mabs(p.x-lastx) > lineWidth or mabs(p.y-lasty) > lineWidth then
				lastx, lasty = p.x, p.y
				if #points == 0 then
					track.minX, track.minY, track.maxX, track.maxY = p.x, p.y, p.x, p.y
				else
					if p.x < track.minX then track.minX = p.x end
					if p.x > track.maxX then track.maxX = p.x end
					if p.y < track.minY then track.minY = p.y end
					if p.y > track.maxY then track.maxY = p.y end
				end
				points[#points+1] = p.x
				points[#points+1] = p.y
				if #points >= 2048 then break end	-- Truncate to avoid drawLine exit
			end
		end

		if #points >= 4 then
--local text = "fixupTrack:showing "..(#points/2).." points for "..stationID.." min:"..track.minX..","..track.minY.." max:"..track.maxX..","..track.maxY
--print(text)
			for i=1,#points,2 do
--print(string.format(",%d,%f,%f", i, points[i], points[i+1]))
				points[i] = points[i] - track.minX
				points[i+1] = points[i+1] - track.minY
			end
			local tw, th = track.maxX-track.minX, track.maxY-track.minY
			if track.showDots then	-- add a line background to highlight it
				track.lineBackground = Graphics { left=track.minX, top=track.minY, width=tw+2, height=th+2 }
				track.lineBackground:setPenColor(0,0,0,1):setPenWidth(lineWidth+2):drawLine(track.points)
				track.lineBackground:setPriority(1888886)
				trackGroup:addChild(track.lineBackground)
			end
			local myWidth = lineWidth
			if track.showDots then myWidth = math.max(math.floor((lineWidth+2)/2),2) end


			if myWidth < 8 then
		
--print(string.format("Graphics:Drawing %d point line width %d", #points/2, myWidth))

				track.line = Graphics { left=track.minX, top=track.minY, width=tw+2, height=th+2 }
				track.line:setPenColor(track.color[1]/255,track.color[2]/255,track.color[3]/255,1):setPenWidth(myWidth):drawLine(track.points)

			else

--print(string.format("Graphics:Expanding %d point line", #points/2))
				local out, back = {}, {}
				local sx, sy = points[1], points[2]
				for p=3, #points, 2 do
					local ex, ey = points[p], points[p+1]
					local dx, dy = ex-sx, ey-sy
					local a = math.atan2(dy, dx)
					local ox, oy = math.sin(a)*myWidth/2, math.cos(a)*myWidth/2

					out[#out+1] = sx+ox
					out[#out+1] = sy+oy
					out[#out+1] = ex+ox
					out[#out+1] = ey+oy
					back[#back+1] = sx-ox
					back[#back+1] = sy-oy
					back[#back+1] = ex-ox
					back[#back+1] = ey-oy
					
					sx, sy = ex, ey
				end
--print(string.format("Graphics:Out has %d Back has %d", #out/2, #back/2))
				for b=#back-1, 1, -2 do
					out[#out+1] = back[b]
					out[#out+1] = back[b+1]
				end
				out[#out+1] = out[1]
				out[#out+1] = out[2]
--print(string.format("Graphics:Polygon has %d", #out/2))

				local tw, th = track.maxX-track.minX, track.maxY-track.minY
				local linealpha = alpha

				local fill = Polygon { width=tw+2, height=th+2, points=out, linecolor={track.color[1]/255,track.color[2]/255,track.color[3]/255, alpha}, linewidth=1, fillcolor={track.color[1]/255,track.color[2]/255,track.color[3]/255, alpha} }
				local bminx, bminy, bminz, bmaxx, bmaxy, bmaxz = fill:getBounds()
				fill:setLeft(track.minX+bminx)
				fill:setTop(track.minY+bminy)
				
				track.line = fill

			end

			track.line:setPriority(1888887)
			trackGroup:addChild(track.line)
			if Application:isDesktop() then
				if track.showDots and dotSize > lineWidth then
					track.dots = Graphics { left=track.minX, top=track.minY, width=tw+2, height=th+2 }
					track.dots:setPenColor(track.color[1]/255,track.color[2]/255,track.color[3]/255,1):setPointSize(dotSize):drawPoints(track.points)
					track.dots:setPriority(1888888)
					trackGroup:addChild(track.dots)
				end
			end
--print('osmTiles:fixupTrack:'..tostring(track.stationID)..':'..tostring(track)..' size:'..tw..'x'..th..' at '..ref.x..','..ref.y)
--print('osmTiles:fixupTrack:'..tostring(track.stationID)..':'..tostring(track)..':Background:'..tostring(track.lineBackground)..' line:'..tostring(track.line)..' dots:'..tostring(track.dots))
		end
	end
end

function osmTiles:showTrack(track, showDots, stationID)
--[[
	if true then
		if type(track) == 'table' then
			print(stationID..":NOT showing Track, "..tostring(#track).." points")
		else
			print(stationID..":NOT showing NIL Track")
		end
		return
	end
]]
	if type(track) == 'table' then
		if not track.activeIndex then
			track.activeIndex = #activeTracks + 1
			activeTracks[track.activeIndex] = track
			if not track.color then
				track.color = colors:getRandomTrackColorArray()
			end
			--print(string.format('showTrack:%d %s Tracks defined', #activeTracks, colors:getColorName(track.color)))
		end
		track.stationID = stationID
		track.showDots = showDots or nil	-- temporarily force it on for testing -- false becomes nil
		fixupTrack(track, true, stationID)	-- Not sure why I have to force a full line rebuild...
	end
end

local function clearPoly(polygon)
	if polygon.line then
		if not polyGroup:removeChild(polygon.line) then
			print('Failed to remove polyLine from polyGroup!')
		end
		polygon.line:dispose()
		polygon.line = nil
	end
	if polygon.fill then
		if not polyGroup:removeChild(polygon.fill) then
			print('Failed to remove polyLine from polyGroup!')
		end
		polygon.fill:dispose()
		polygon.fill = nil
	end
	if polygon.lines then
		for _, line in ipairs(polygon.lines) do
			if not polyGroup:removeChild(line) then
				print('Failed to remove polyLine from polyGroup!')
			end
			line:dispose()
		end
		polygon.lines = nil
	end
	if polygon.fills then
		for _, fill in ipairs(polygon.fills) do
			if not polyGroup:removeChild(fill) then
				print('Failed to remove polyLine from polyGroup!')
			end
			fill:dispose()
		end
		polygon.fills = nil
	end
	if polygon.arrows then
		for i, a in pairs(polygon.arrows) do
			if not polyGroup:removeChild(a) then
				print('Failed to remove arrow from polyGorup!')
			end
			a:dispose()
		end
		polygon.arrows = nil
	end
	polygon.points = nil
end

local function isPointOnScreen(x20, y20)
		return x20 >= tileGroup.minX20
		and x20 < tileGroup.maxX20
		and y20 >= tileGroup.minY20
		and y20 < tileGroup.maxY20
end

local getSymbolScale	-- forward function reference

local function scaleReducePoly(stationID, polygon, arrows, lineWidth, alpha, filled, color)
	if not polygon.xy20 then
		local tstart, telapsed
		tstart = MOAISim.getDeviceTime()
		local points = {}
		for i=1,#polygon,2 do
			local x20, y20 = osmTileNum(polygon[i], polygon[i+1], 20)
			if not x20 or not y20 then
				print("osmTiles:fixupPoly:"..stationID.."["..i.."] out of range, lat:"..polygon[i].." lon:"..polygon[i+1])
			else
				points[#points+1] = x20
				points[#points+1] = y20
--print(string.format("xy20,%d,%f,%f", i, x20, y20))
			end
		end
		polygon.xy20 = points
		telapsed = (MOAISim.getDeviceTime()-tstart)*1000
		if telapsed > 2 then print(string.format("NWS:scaleReducePoly:xy20(%s) %d points took %dmsec", stationID, #points, telapsed)) end
	end
	local xy20 = polygon.xy20

	local points = {}

--	local ref = { lat=polygon[1], long=polygon[2] }
	local lastx, lasty = -1, -1
	local mabs = math.abs
	local width, height = tileGroup.width, tileGroup.height
	local minDim = math.min(width, height)
	
	local line, fill = nil, nil

--	print(string.format("tileGroup range x:%d-%d y:%d-%d", tileGroup.minX20, tileGroup.maxX20, tileGroup.minY20, tileGroup.maxY20))
--	print(string.format("tileGroup z:%d x:%d-%d y:%d-%d", zoom, tileGroup.minX20*zoomDiv, tileGroup.maxX20*zoomDiv, tileGroup.minY20*zoomDiv, tileGroup.maxY20*zoomDiv))
	
	for i=1,#xy20,2 do
		local x20, y20 = xy20[i], xy20[i+1]
		if not x20 or not y20 then
			print("osmTiles:fixupPoly:"..stationID.."["..i.."] out of range, lat:"..xy20[i].." lon:"..xy20[i+1])
		--else print("osmTiles:fixupPoly:"..stationID.."["..i.."] lat:"..xy20[i].." lon:"..xy20[i+1].." x,y:"..x20..","..y20)
		end
		if x20 ~= fromx or y20 ~= fromy then	-- Actually have a line segment
			local x, y = wrapX(x20*zoomDiv,polyGroup.x), y20*zoomDiv
			
--print(string.format("%d,%d,%d", i, x20, y20))			
			
--			if #points == 0 or mabs(x-lastx) > lineWidth or mabs(y-lasty) > lineWidth then
			if #points == 0 or mabs(x-lastx) > 1 or mabs(y-lasty) > 1 then
				if #points > 0 and mabs(x-lastx) > zoomDelta/2 then	-- Skip screen-crossing points
					-- I'd really like to split into two lines, but not yet!
				else
					if #points == 0 then
						polygon.minX, polygon.minY, polygon.maxX, polygon.maxY = x, y, x, y
					else
						if x < polygon.minX then polygon.minX = x end
						if x > polygon.maxX then polygon.maxX = x end
						if y < polygon.minY then polygon.minY = y end
						if y > polygon.maxY then polygon.maxY = y end
						
						local dx, dy = x-lastx, y-lasty
						local length = math.sqrt(dx*dx+dy*dy)
						if arrows and length > minDim/4 then	-- Long enough for an arrow
	--						print("Need Arrow at "..tostring(lastx)..","..tostring(lasty).." to "..tostring(x)..","..tostring(y))
							table.insert(arrows, {fromx=lastx, fromy=lasty, tox=x, toy=y})
						end
					end
					points[#points+1] = x
					points[#points+1] = y
--print(string.format("xy,%d,%f,%f", i, x, y))
					local maxPoints = 20480
					if #points >= maxPoints then
--print("fixupPoly:"..stationID.." has "..tostring(#xy20/2).." points, ?reduced? to > "..tostring(maxPoints/2))
						--break
					end	-- Truncate to avoid drawLine exit
					lastx, lasty = x, y
				end
			end
		end
	end
	

	local function Intersect(points, visible, intercept)
		if #points < 4 then return {} end
		local fromx, fromy
		if filled then
			fromx, fromy = points[#points-1], points[#points]
		else fromx, fromy = points[1], points[2]
		end
		local fromInside = visible(fromx, fromy)
		local pn = {}
		for i=1, #points, 2 do
			local x, y = points[i], points[i+1]
			local inside = visible(x,y)
			if inside then
				if not fromInside then
					local nx, ny = intercept(fromx, fromy, x, y)
					pn[#pn+1] = nx
					pn[#pn+1] = ny
--print(string.format("%s-1,%d,%f,%f", tostring(intercept), i, nx, ny))
				end
				pn[#pn+1] = x
				pn[#pn+1] = y
--print(string.format("%s-2,%d,%f,%f", tostring(intercept), i, x, y))
			elseif fromInside then
				local nx, ny = intercept(fromx, fromy, x, y)
				pn[#pn+1] = nx
				pn[#pn+1] = ny
--print(string.format("%s-3,%d,%f,%f", tostring(intercept), i, nx, ny))
			end
			fromx, fromy, fromInside = x,y,inside
		end
		return pn
	end
	
	local before = #points
	local minX, maxX, minY, maxY = tileGroup.minX20*zoomDiv, tileGroup.maxX20*zoomDiv, tileGroup.minY20*zoomDiv, tileGroup.maxY20*zoomDiv
	if stationID == "" then
		for p=1,#points,2 do
			print(string.format("NWS:%s[%d]=%d,%d", stationID, p, points[p], points[p+1]))
		end
	end
	points = Intersect(points,
					function (x,y)
						return x >= minX
					end,
					function (x1,y1,x2,y2)
						local slope = (y2-y1) / (x2 - x1)
						local y = slope*(minX-x1)+y1
						return minX, y
					end)	
--	print(string.format("NWS:%s From %d to(minX=%d) %d zoom %d", stationID, before, minX, #points, zoom))
	points = Intersect(points,
					function (x,y)
						return x <= maxX
					end,
					function (x1,y1,x2,y2)
						local slope = (y2-y1) / (x2 - x1)
						local y = slope*(maxX-x1)+y1
						return maxX, y
					end)
		
--	print(string.format("NWS:%s From %d to(maxX=%d) %d zoom %d", stationID, before, maxX, #points, zoom))
	points = Intersect(points,
					function (x,y)
						return y >= minY
					end,
					function (x1,y1,x2,y2)
						local slope =  (x2 - x1) / (y2-y1)
						local x = slope*(minY-y1)+x1
						return x, minY
					end)
--	print(string.format("NWS:%s From %d to(minY=%d) %d zoom %d", stationID, before, minY, #points, zoom))
	points = Intersect(points,
					function (x,y)
						return y <= maxY
					end,
					function (x1,y1,x2,y2)
						local slope =  (x2 - x1) / (y2-y1)
						local x = slope*(maxY-y1)+x1
						return x, maxY
					end)
--	print(string.format("NWS:%s From %d to(maxY=%d) %d zoom %d", stationID, before, maxY, #points, zoom))
	local after = #points
--	print(string.format("NWS:%s From %d to %d zoom %d %d,%d %d,%d size %d x %d", stationID, before, after, zoom, polygon.minX, polygon.minY, polygon.maxX, polygon.maxY, polygon.maxX-polygon.minX, polygon.maxY-polygon.minY))
	if stationID:sub(1,6) == "" and #points > 0 then
		print(string.format("printing %d points for %s", #points, stationID))
		for p=1,#points,2 do
			print(string.format("NWS:%s,%d,%d,%d", stationID, p, points[p], points[p+1]))
		end
	end

	if #points >= 4 then
--print(string.format("fixupPoly:%s %d/%d min %d,%d max %d,%d adj min %d,%d max %d,%d",
--					stationID, #points, #xy20, polygon.minX, polygon.minY, polygon.maxX, polygon.maxY,
--					polygon.minX-polygon.minX, polygon.minY-polygon.minY, polygon.maxX-polygon.minX, polygon.maxY-polygon.minY))
		for i=1,#points,2 do
			points[i] = points[i] - polygon.minX
			points[i+1] = points[i+1] - polygon.minY
if stationID:sub(1,6) == "" then
	print(string.format("NWS:%s,%d,%d,%d", stationID, i, points[i], points[i+1]))
end
		end
		local tw, th = polygon.maxX-polygon.minX, polygon.maxY-polygon.minY
		
		--if not polygon.minSize then
		--	print(string.format("scaleReducePoly: NO polygon.minSize!"))
		--else
		--	print(string.format("scaleReducePoly: tw x th %dx%d vs %.2f minSize=%d*%.2f*1.1",
		--			tw, th, polygon.minSize * getSymbolScale() * 1.1, polygon.minSize, getSymbolScale()))
		--end

		if not polygon.minSize
		or (tw > polygon.minSize * getSymbolScale() * 1.1
			and th > polygon.minSize * getSymbolScale() * 1.1)
		then
		local myWidth = lineWidth
		local linealpha = alpha
		if filled then linealpha = 1 end
		if filled then
--[[
			polygon.line = Graphics { left=polygon.minX, top=polygon.minY, width=tw+2, height=th+2 }
--			polygon.line:setPenColor(polygon.color[1]/255*alpha,polygon.color[2]/255*alpha,polygon.color[3]/255*alpha,alpha):setPenWidth(myWidth):fillFan(polygon.points)
			polygon.line:setColor(polygon.color[1]/255,polygon.color[2]/255,polygon.color[3]/255, alpha)
			polygon.line:setPenWidth(math.floor(myWidth*10))
			polygon.line:drawLine(polygon.points)
--				polygon.line:setPenColor(polygon.color[1]/255*alpha,polygon.color[2]/255*alpha,polygon.color[3]/255*alpha,alpha):setPenWidth(myWidth):fillFan(polygon.points)
]]
--			fill = Polygon { left=polygon.minX, top=polygon.minY, width=tw+2, height=th+2, points=points }
			fill = Polygon { width=tw+2, height=th+2, points=points, linecolor={color[1]/255,color[2]/255,color[3]/255, linealpha}, linewidth=myWidth, fillcolor={color[1]/255,color[2]/255,color[3]/255, alpha} }
			local bminx, bminy, bminz, bmaxx, bmaxy, bmaxz = fill:getBounds()
			fill:setLeft(polygon.minX+bminx)
			fill:setTop(polygon.minY+bminy)
			--fill:setColor(color[1]/255,color[2]/255,color[3]/255, alpha)
			fill:setPriority(1888888)
			polyGroup:addChild(fill)
--print("NWS:Filled Polygon "..stationID.." width:"..tostring(myWidth).." alpha:"..tostring(alpha).." left/top:"..tostring(polygon.minX).."/"..tostring(polygon.minY))
--else print("Graphics:NWS:NOT Filled Polygon "..stationID.." width:"..tostring(myWidth).." alpha:"..tostring(alpha).." left/top:"..tostring(polygon.minX).."/"..tostring(polygon.minY))
		end

		if myWidth < 108 then
	
--print(string.format("Graphics:Drawing %d point poly width %d", #points/2, myWidth))

			line = Graphics { left=polygon.minX, top=polygon.minY, width=tw+2, height=th+2 }
			line:setColor(color[1]/255,color[2]/255,color[3]/255, linealpha)
			line:setPenWidth(myWidth)
			line:drawLine(points)
			line:setPriority(1888887)
			polyGroup:addChild(line)
		else

--print(string.format("Graphics:Expanding %d point poly", #points/2))
			local out, back = {}, {}
			local sx, sy = points[1], points[2]
			for p=3, #points, 2 do
				local ex, ey = points[p], points[p+1]
				local dx, dy = ex-sx, ey-sy
				local a = math.atan2(dx, dy) + math.pi/2
				local ox, oy = math.sin(a)*myWidth/2, math.cos(a)*myWidth/2

--print(string.format("Graphics:%.2f,%.2f->%.2f,%.2f %.0f degrees offset %.2f,%.2f",
--					sx, sy, ex, ey, a*180/math.pi, ox, oy))

				out[#out+1] = sx+ox
				out[#out+1] = sy+oy
				out[#out+1] = ex+ox
				out[#out+1] = ey+oy
				back[#back+1] = sx-ox
				back[#back+1] = sy-oy
				back[#back+1] = ex-ox
				back[#back+1] = ey-oy
				
				sx, sy = ex, ey
			end
--print(string.format("Graphics:Out has %d Back has %d", #out/2, #back/2))
			for b=#back-1, 1, -2 do
				out[#out+1] = back[b]
				out[#out+1] = back[b+1]
			end
			out[#out+1] = out[1]
			out[#out+1] = out[2]
			
--print(string.format("Graphics:Polygon has %d", #out/2))
--for o=1, #out, 2 do
--print(string.format("Graphics:out[%d] %.2f,%.2f", o/2+1, out[o], out[o+1]))
--end

			local tw, th = polygon.maxX-polygon.minX, polygon.maxY-polygon.minY

			fill = Polygon { width=tw+2, height=th+2, points=out, linecolor={color[1]/255,color[2]/255,color[3]/255, alpha}, linewidth=1, fillcolor={color[1]/255,color[2]/255,color[3]/255, alpha} }
			local bminx, bminy, bminz, bmaxx, bmaxy, bmaxz = fill:getBounds()
			fill:setLeft(polygon.minX+bminx)
			fill:setTop(polygon.minY+bminy)
			polyGroup:addChild(fill)
			line = fill
			fill = nil
			
--			line = Graphics { left=polygon.minX, top=polygon.minY, width=tw+2, height=th+2 }
--			line:setColor(0,0,1,0.30)
--			line:setPenWidth(2)
--			line:drawLine(points)
--			polyGroup:addChild(line)

--			fill = Graphics { left=polygon.minX, top=polygon.minY, width=tw+2, height=th+2 }
--			fill:setColor(1,0,0,0.30)
--			fill:setPenWidth(2)
--			fill:drawLine(out)
--			polyGroup:addChild(fill)
--			line = fill

--			line = Graphics { left=polygon.minX, top=polygon.minY, width=tw+2, height=th+2 }
--			line:setColor(0,1,0,0.30)
--			line:setPenWidth(2)
--			line:drawLine(back)
--			polyGroup:addChild(line)

--			line = Graphics { left=polygon.minX, top=polygon.minY, width=tw+2, height=th+2 }
--			line:setColor(1,0,0,1)
--			line:setPenWidth(2)
--			line:drawLine(out)
--			polyGroup:addChild(line)

--[[
			local dots = Graphics { left=polygon.minX, top=polygon.minY, width=tw+2, height=th+2 }
			dots:setPenColor(0,0,0,1):setPointSize(10):drawPoints(out)
			dots:setPriority(1888888)
			polyGroup:addChild(dots)

			dots = Graphics { left=polygon.minX, top=polygon.minY, width=tw+2, height=th+2 }
			dots:setPenColor(0,0,0,1):setPointSize(10):drawPoints(points)
			dots:setPriority(1888888)
			polyGroup:addChild(dots)
]]			
--			line = fill
		end
		else
			--print(string.format("scaleReducePoly: tw x th %dx%d < %.2f minSize=%d*%.2f*1.1",
			--		tw, th, polygon.minSize * getSymbolScale() * 1.1, polygon.minSize, getSymbolScale()))
		end
	--else
		--print(string.format("scaleReducePoly: Only %d points!", #points))
	end
	return line, fill
end

local function fixupPoly(polygon, stationID)
	stationID = stationID or polygon.stationID
	polygon.stationID = stationID
	stationID = stationID or "*unknown*"
	if polygon then
local tstart, telapsed
tstart = MOAISim.getDeviceTime()

		clearPoly(polygon)
		
		local pCount = 0
		local arrows = polygon.showArrows and {} or nil

		if type (polygon[1]) == 'table' then
			for i, poly in ipairs(polygon) do
				pCount = pCount + #poly
				local line, fill = scaleReducePoly(stationID.."["..tostring(i).."]", poly, arrows, polygon.lineWidth or 1, polygon.alpha, polygon.filled, polygon.color)
				if not polygon.lines then polygon.lines = {} end
				polygon.lines[#polygon.lines+1] = line
				if fill then
					if not polygon.fills then polygon.fills = {} end
					polygon.fills[#polygon.fills+1] = fill
				end
			end
		else
			pCount = pCount + #polygon
			polygon.line, polygon.fill = scaleReducePoly(stationID, polygon, arrows, polygon.lineWidth or 1, polygon.alpha, polygon.filled, polygon.color)
		end
	
		if arrows and #arrows then
			local tw, th = polygon.maxX-polygon.minX, polygon.maxY-polygon.minY
			local myWidth = polygon.lineWidth or 1
			local linealpha = polygon.alpha
			if filled then linealpha = 1 end
			for i,t in pairs(arrows) do
				local dx, dy = t.tox-t.fromx, t.toy-t.fromy
				local atx, aty = t.fromx+dx/4, t.fromy+dy/4
				local ttx, tty = atx/zoomDiv, aty/zoomDiv
				local visible = (ttx >= tileGroup.minX20 and ttx <= tileGroup.maxX20
							and tty >= tileGroup.minY20 and tty <= tileGroup.maxY20)
--print(string.format("Arrow at %d %d or %d %d Tile %d->%d %d->%d %s",
--					atx, aty, atx/zoomDiv, aty/zoomDiv,
--					tileGroup.minX20, tileGroup.maxX20, tileGroup.minY20, tileGroup.maxY20,
--					visible and "visible" or "off-screen"))
				if visible then
					local a = math.atan2(dx, dy) - math.pi/2
					--a = 3*math.pi/4
					local s = config.Screen.scale * 4
					local arrowpoints = {}
					local function addPoint(x,y)
						local x1 = x*math.cos(a)+y*math.sin(a)
						local y1 = y*math.cos(a)-x*math.sin(a)
						table.insert(arrowpoints,atx-polygon.minX+x1*s)
						table.insert(arrowpoints,aty-polygon.minY+y1*s)
					end
					addPoint(-14,6) addPoint(0,0) addPoint(-14,-6) -- addPoint(4,0) addPoint(12,0)

					local arrow = Graphics { left=polygon.minX, top=polygon.minY, width=tw+2, height=th+2 }
					print("showArrows:polygon("..tostring(polygon.stationID).." color "..printableTable(polygon.color))
					arrow:setPenColor(polygon.color[1]/255,polygon.color[2]/255,polygon.color[3]/255, linealpha*3/4)
					arrow:setPenWidth(math.max(myWidth/2,1))
					arrow:drawLine(arrowpoints)
	--[[			if polygon.filled then
			polygon.line:setPenColor(polygon.color[1]/255*alpha,polygon.color[2]/255*alpha,polygon.color[3]/255*alpha,alpha):setPenWidth(myWidth):fillFan(polygon.points)
		end]]
					arrow:setPriority(1888889)
					if not polygon.arrows then polygon.arrows = {} end
					table.insert(polygon.arrows, arrow)
					polyGroup:addChild(arrow)
				end
			end
		end
--telapsed = (MOAISim.getDeviceTime()-tstart)*1000
--if telapsed > 10 then
--	local aCount
--	if arrows then aCount = #arrows else aCount = 0 end
	--print("osmTiles:fixupPoly("..tostring(stationID)..") "..tostring(pCount).."/"..tostring(aCount).." points/arrows Took "..telapsed.."ms")
--end
	end
end

function osmTiles:showPolygon(polygon, stationID)
	if type(polygon) == 'table' then
		if not polygon.minSize then print(string.format("osmtiles:showPolygon(%s) minSize=%s", tostring(stationID), tostring(polygon.minSize))) end

	--print("showPolygon:"..tostring(stationID).." "..tostring(#polygon).." points")
		if not polygon.activeIndex then
			polygon.activeIndex = #activePolys + 1
			activePolys[polygon.activeIndex] = polygon
			if not polygon.color then
				polygon.color = colors:getRandomTrackColorArray()
--				print("showPolygon:RandomColor("..stationID..") is "..printableTable(polygon.color))
			else
--				print("showPolygon:SpecifiedColor("..stationID..") is "..printableTable(polygon.color))
			end
			
			if not polygon.alpha then
				print("showPolygon:Defaulting "..stationID.." opacity to 50%")
				polygon.alpha = 0.5
			end
		end
		polygon.stationID = stationID
		fixupPoly(polygon, stationID)
	end
	return polygon
end

function osmTiles:removePolygon(polygon)
	if polygon then
		clearPoly(polygon)
		if polygon.activeIndex then
			local index = polygon.activeIndex
			polygon.activeIndex = nil	-- make sure it remembers it's gone!
			local lastIndex = #activePolys
			if index ~= lastIndex then
				activePolys[index] = activePolys[lastIndex]
				activePolys[index].activeIndex = index	-- record the new index
			end
			activePolys[lastIndex] = nil
		end
	end
end

function osmTiles:translateXY(x, y)	-- returns x,y translated from map to screen coords
	local tile = tileGroup.tiles[1]	-- First tile is at center
	local xo, yo = -tile.xTile*tileSize, -tile.yTile*tileSize
	local xl = xo+tile.x+tileGroup.tilesGroup.xOffset
	local yl = yo+tile.y+tileGroup.tilesGroup.yOffset
	return x+xl, y+yl
end

function osmTiles:whereIS(lat, lon)	-- returns x,y on screen or nil, nil if not visible
	local x20, y20 = osmTileNum(lat, lon, 20)
	--if not isPointOnScreen(x20, y20) then return nil, nil end
	local x, y = wrapX(x20*zoomDiv,trackGroup.x), y20*zoomDiv
	return x, y
end


local log2 = math.log(2)
getSymbolScale = function ()
	local horzScale, vertScale = osmTiles:rangeLatLon()
	local scale = math.max(horzScale, vertScale)

	if (config.Screen.SymbolSizeAdjust ~= 0) then
		scale = scale / 2.0^config.Screen.SymbolSizeAdjust
	end

	-- 1.375 - log2(x) / 8  per Mykle N7JZT 
	local scale2 = math.log(scale)/log2	-- Log base 2
	local result2 = 1.375 - scale2/8
	result2 = math.min(2,math.max(0.5,result2))	-- Never >2x or smaller than x/2
	return result2
end

local function showSymbol(symbol)
	if not symbol.inGroup then
		symbolGroup.groupCount = symbolGroup.groupCount + 1
		symbolGroup:addChild(symbol.symbol)
		symbol.inGroup = true
	end
	if symbol.label and not symbol.label.inGroup then
		labelGroup:addChild(symbol.label)
		symbol.label.inGroup = true
	end
end

local function hideSymbol(symbol)
	if symbol.inGroup then
		symbolGroup.groupCount = symbolGroup.groupCount - 1
		if not symbolGroup:removeChild(symbol.symbol) then
			local text = 'osmTiles:hideSymbol:symbol('..type(symbol.symbol)..') NOT removed from symbolGroup!'
			print('******************* '..text)
			toast.new(text)
		end
		symbol.inGroup = false
	end
	if symbol.label and symbol.label.inGroup then
		if not labelGroup:removeChild(symbol.label) then
			local text = 'osmTiles:hideSymbol:label('..type(symbol.label)..') NOT removed from labelGroup!'
			print('******************* '..text)
			toast.new(text)
		end
		symbol.label.inGroup = false
	end
end

local function fixupSymbol(symbolLabel, scale)
--	print("fixupSymbol:"..symbolLabel.stationID)

	showSymbol(symbolLabel)

	if not scale then scale = getSymbolScale() end
--print("Symbol scale:"..tostring(scale).." individual "..tostring(symbolLabel.symbol.scale))
	if type(symbolLabel.symbol.scale) == 'nil' then symbolLabel.symbol.scale = 1.0 end
	symbolLabel.x, symbolLabel.y = wrapX(symbolLabel.x20*zoomDiv, symbolGroup.x), symbolLabel.y20*zoomDiv
	symbolLabel.symbol:setLoc(symbolLabel.x, symbolLabel.y)
	symbolLabel.symbol:setScl(scale*symbolLabel.symbol.scale, scale*symbolLabel.symbol.scale, 1.0)
--if shouldIShowIt(symbolLabel.stationID) then print("osmTiles:getsymbolLabel:"..symbolLabel.stationID.." size "..symbolLabel:getWidth().."x"..symbolLabel:getHeight().." scale:"..scale) end
	if symbolLabel.label then
		--symbolLabel.label:setRect(0, 0, TextLabel.MAX_FIT_WIDTH, TextLabel.MAX_FIT_HEIGHT)
		--symbolLabel.label:setTextSize(math.floor(symbolLabel.label.orgTextSize*scale))
		--symbolLabel.label:fitSize()
		symbolLabel.label:setLoc(symbolLabel.x+symbolLabel.label.xOffset*scale, symbolLabel.y)
		symbolLabel.label:setScl(scale, scale, 1.0)
	end
end

local function isSymbolVisible(symbol)
		return symbol.x20 >= tileGroup.minX20
		and symbol.x20 < tileGroup.maxX20
		and symbol.y20 >= tileGroup.minY20
		and symbol.y20 < tileGroup.maxY20
end

local function fixupSymbols(why, forceit)
--print("fixupSymbols("..tostring(why)..")")
	local start = MOAISim.getDeviceTime()
	local tile = tileGroup.tiles[1]	-- First tile is at center
	local xo, yo = -tile.xTile*tileSize, -tile.yTile*tileSize
	local xl = xo+tile.x+tileGroup.tilesGroup.xOffset
	local yl = yo+tile.y+tileGroup.tilesGroup.yOffset
	
	if not symbolGroup.offsetVersion
	or symbolGroup.offsetVersion ~= tileGroup.offsetVersion
	or forceit then

	if not labelGroup.x
	or math.abs(labelGroup.x-xl) > 0.5
	or math.abs(labelGroup.y-yl) > 0.5 then
	else print('osmTiles:fixupSymbols:'..tostring(why)..':NOT moving('..string.format("%.2f %.2f", labelGroup.x-xl, labelGroup.y-yl)..') '..#allSymbols..' symbols and '..#activeTracks..' tracks took '..((MOAISim.getDeviceTime()-start)*1000)..'ms **************************************************')
	end
	
	symbolGroup.offsetVersion = tileGroup.offsetVersion

	labelGroup.x, labelGroup.y = xl, yl
	labelGroup:setLoc(labelGroup.x, labelGroup.y)
	symbolGroup.x, symbolGroup.y = xl, yl
	symbolGroup:setLoc(symbolGroup.x, symbolGroup.y)
	trackGroup.x, trackGroup.y = xl, yl
	trackGroup:setLoc(trackGroup.x, trackGroup.y)
	polyGroup.x, polyGroup.y = xl, yl
	polyGroup:setLoc(polyGroup.x, polyGroup.y)
	
	if tileGroup.wrapped
	or forceit
	or not symbolGroup.tileVersion
	or not symbolGroup.sizeVersion 
	or symbolGroup.tileVersion ~= tileGroup.tileVersion
	or symbolGroup.sizeVersion ~= tileGroup.sizeVersion then

		symbolGroup.tileVersion = tileGroup.tileVersion
		symbolGroup.sizeVersion = tileGroup.sizeVersion

local tstart, telapsed
tstart = MOAISim.getDeviceTime()
		for n = 1, #activeTracks do
			fixupTrack(activeTracks[n], true)
		end
telapsed = (MOAISim.getDeviceTime()-tstart)*1000
if telapsed > 10 then print("osmTiles:fixupSymbols:fixupTracks("..tostring(#activeTracks)..") Took "..telapsed.."ms") end
tstart = MOAISim.getDeviceTime()
		for n = 1, #activePolys do
			fixupPoly(activePolys[n])
		end
telapsed = (MOAISim.getDeviceTime()-tstart)*1000
if telapsed > 10 then print("osmTiles:fixupSymbols:fixupPolys("..tostring(#activePolys)..") Took "..telapsed.."ms") end
tstart = MOAISim.getDeviceTime()
		local offScreen, onScreen = 0, 0
		local scale = getSymbolScale()
		for n = 1, #allSymbols do
			local symbol = allSymbols[n]
			if isSymbolVisible(symbol) then
				if symbol.inGroup or symbolGroup.groupCount < MaxSymbols then
					fixupSymbol(symbol, scale)
				else hideSymbol(symbol)
				end
				onScreen = onScreen + 1
			else
				hideSymbol(symbol)
				offScreen = offScreen + 1
			end
		end
		if labelGroup.visible then
			if symbolGroup.groupCount < MaxSymbols / 2 then
				tileGroup:addChild(labelGroup)
			else tileGroup:removeChild(labelGroup)
			end
		end
local elapsed = (MOAISim.getDeviceTime()-start)*1000
if elapsed > 10 then print('osmTiles:fixupSymbols:'..tostring(why)..':fixing '..#allSymbols..' symbols (on/off:'..onScreen..'/'..offScreen..')(group:'..tostring(symbolGroup.groupCount)..'?'..tostring(symbolGroup:getNumChildren())..') and '..#activeTracks..' tracks took '..elapsed..'ms zoom:'..zoom) end
	else
local elapsed = (MOAISim.getDeviceTime()-start)*1000
if elapsed > 10 then print('osmTiles:fixupSymbols:'..tostring(why)..':NOT fixing '..#allSymbols..' symbols and '..#activeTracks..' tracks took '..elapsed..'ms') end
--print(string.format("fixupSymbols:%s %s %d %d %d %d", (tileGroup.wrapped and "WRAPPED" or ""), (forceit and "FORCE " or ""),symbolGroup.tileVersion, tileGroup.tileVersion, symbolGroup.sizeVersion, tileGroup.sizeVersion))
	end	-- tile/sizeVersion
--else print(string.format("fixupSymbols:%s%d %d", (forceit and "FORCE " or ""), symbolGroup.offsetVersion, tileGroup.offsetVersion))
	end	-- offsetVersion
--[[
print(string.format('symbolGroup: @ %i,%i Tile %i,%i @ %i,%i Offset %i %i',
					symbolGroup.x, symbolGroup.y,
					tile.xTile, tile.yTile,
					tile.x, tile.y,
					tileGroup.tilesGroup.xOffset, tileGroup.tilesGroup.yOffset))
]]
--	if tileGroup:getChildAt(tileGroup:getNumChildren()) ~= symbolGroup then
--		print(string.format('tileGroup[%i]=%s symbols:%s', tileGroup:getNumChildren(), tostring(tileGroup:getChildAt(tileGroup:getNumChildren())), tostring(symbolGroup)))
--		tileGroup:addChild(trackGroup)
--		tileGroup:addChild(symbolGroup)
--		print(string.format('tileGroup[%i]=%s symbols:%s', tileGroup:getNumChildren(), tostring(tileGroup:getChildAt(tileGroup:getNumChildren())), tostring(symbolGroup)))
--	end
end

function osmTiles:refreshMap()
	fixupSymbols("refreshMap", true)
	invokeCallbacks('refresh')
end

function osmTiles:removeSymbol(symbolLabel)	-- caller must nil out reference!

	hideSymbol(symbolLabel)

	if symbolLabel.allIndex then
		local index = symbolLabel.allIndex
		symbolLabel.allIndex = nil	-- make sure it remembers it's gone!
		local lastIndex = #allSymbols
		if index ~= lastIndex then
			allSymbols[index] = allSymbols[lastIndex]
			allSymbols[index].allIndex = index	-- record the new index
		end
		allSymbols[lastIndex] = nil
		-- print('Removing allSymbols['..index..'] leaves '..#allSymbols..' (was '..lastIndex..')')
	end
end

function osmTiles:showSymbol(lat, lon, symbolLabel, stationID)

	if not symbolLabel then
		local info = debug.getinfo( 2, "Sl" )
		local where = info.source..':'..info.currentline
		if where:sub(1,1) == '@' then where = where:sub(2) end
		print("Attempt to show nil symbolLabel from "..where)
		return
	end
	
	symbolLabel.stationID = stationID
	
	local x20, y20 = osmTileNum(lat, lon, 20)
	if not x20 or not y20 then
		print('osmTiles:showSymbol:Invalid Lat=%.5f Lon=%.5f, relocated to 0,0', lat, lon)
		x20, y20 = osmTileNum(0, 0, 20)
	end

	if not symbolLabel.allIndex then
		symbolLabel.allIndex = #allSymbols+1
		symbolLabel.stationID = stationID
		allSymbols[symbolLabel.allIndex] = symbolLabel
		--print(symbolLabel.allIndex..' symbols defined')
	elseif allSymbols[symbolLabel.allIndex] ~= symbolLabel then
		text = 'allSymbols['..tostring(symbolLabel.allIndex)..'] for '..tostring(allSymbols[symbolLabel.allIndex].stationID)..' not '..tostring(stationID)
		toast.new(text)
		print('******************* allSymbols['..tostring(symbolLabel.allIndex)..'] is '..tostring(allSymbols[symbolLabel.allIndex])..' for '..tostring(allSymbols[symbolLabel.allIndex].stationID)..' not '..tostring(symbolLabel)..' for '..tostring(stationID))
	end
	symbolLabel.lat, symbolLabel.lon = lat, lon
	symbolLabel.x20, symbolLabel.y20 = x20, y20
--print(string.format('symbolLabel:%s %i @ %i,%i', tostring(symbolLabel), 20, symbolLabel.x20, symbolLabel.y20))

	--if not shouldIShowIt(stationID) then return end

	if isSymbolVisible(symbolLabel) then
		if symbolLabel.inGroup or symbolGroup.groupCount < MaxSymbols then
			fixupSymbol(symbolLabel)
			if labelGroup.visible then
				if symbolGroup.groupCount < MaxSymbols / 2 then
					tileGroup:addChild(labelGroup)
				else tileGroup:removeChild(labelGroup)
				end
			end
		end
	end
end

function osmTiles:showAll()
	if #allSymbols > 0 then
		local minx, miny, maxx, maxy
		minx, miny = allSymbols[1].x20, allSymbols[1].y20
		maxx, maxy = minx, miny

		for i, s in ipairs(allSymbols) do
			if s.x20 < minx then minx = s.x20 end
			if s.y20 < miny then miny = s.y20 end
			if s.x20 > maxx then maxx = s.x20 end
			if s.y20 > maxy then maxy = s.y20 end
		end
		local lat2, lon2 = osmTileLatLon((maxx+minx)/2,(maxy+miny)/2,20)
		local xs = (maxx - minx)
		local ys = (maxy - miny)
		local z = 20	-- zoom for xs/ys
		print("move starting with "..xs.."x"..ys.." at zoom 20")
		while xs > tileGroup.width or ys > tileGroup.height do
			z = z - 1
			xs = xs / 2
			ys = ys / 2
		end
		z = z - 8	-- Don't know WHY I need this!  (other than 2^8 = 256)
		print("moving to "..tostring(lat2).." "..tostring(lon2).." zoom "..z.." for "..xs..'x'..ys..' vs '..tileGroup.width.."x"..tileGroup.height)
		osmTiles:moveTo(lat2, lon2, z)
		print("moved to "..tostring(lat2).." "..tostring(lon2).." zoom "..z.." for "..xs..'x'..ys..' vs '..tileGroup.width.."x"..tileGroup.height)
	end
end

local function displayTileImage(n, image, x, y, z)
if debugging then print(string.format('displayTileImage:[%d] %d,%d,%d...', n, x, y, z)) end
	if image then
		tileGroup.tiles[n]:removeChildAt(1)
if tileGroup.tiles[n]:getChildAt(1) or tileGroup.tiles[n]:getNumChildren() > 0 then
	print('displayTileImage['..n..'] '..tileGroup.tiles[n]:getNumChildren()..' ORPHAN!  from '..tileGroup.tiles[n].from)
	tileGroup.tiles[n]:removeChildren()
	print('displayTileImage['..n..'] '..tileGroup.tiles[n]:getNumChildren()..' ORPHAN!  from '..tileGroup.tiles[n].from)
end
		tileGroup.tiles[n]:addChild(image)
if tileGroup.tiles[n]:getNumChildren() > 1 then
	print('displayTileImage['..n..'] '..tileGroup.tiles[n]:getNumChildren()..' EXTRA!  from '..tileGroup.tiles[n].from)
end
		tileGroup.tiles[n].from = 'displayTileImage'
--if debugging then print('displayTileImage:getWidth/Height') end
		image.x = image:getWidth()/2
		image.y = image:getHeight()/2
--if debugging then print('displayTileImage:gotWidth('..image.x..')/Height('..image.y..')') end

if debugging then print(string.format("displayTileImage:[%d]<-%d,%d,%d goodTile!", n, x, y, z)) end
		tileGroup.tiles[n].xTile, tileGroup.tiles[n].yTile, tileGroup.tiles[n].zTile = x, y, z
		tileGroup.tiles[n].goodTile = true
		
		--if tapTimer then tileGroup.zoomGroup.alpha = 0.75 end	-- Allow zooming again
		--tileGroup.tile.alpha = tileAlpha
		--fixupSymbols()
		--[[if tileGroup.symbolLabel then
			osmTiles:showSymbol(tileGroup.symbolLabel.lat, tileGroup.symbolLabel.lon, tileGroup.symbolLabel)
		end]]
	else
		print ('displayTileImage(NIL)!')
	end
if debugging then print('displayTileImage:Done') end
end

function osmTiles:getMBTilesCounts()
	return tilemgr:getMBTilesCounts()
end

function osmTiles:newMBTiles()
	print("osmTiles:newMBTiles("..tostring(config.Map.MBTiles)..")")
	tilemgr:newMBTiles()
	self:moveTo()	-- All nils forces a map reloaded
end

function osmTiles:getQueueStats()	-- returns count, maxcount, pushcount, popcount
	return tilemgr:getQueueStats()
end

local function osmLoadTile(n,x,y,z,force)
	local tstart = MOAISim.getDeviceTime()
	x = math.floor(x)
	y = math.floor(y)
	if debugging then print(string.format("osmLoadTile[%d] %d,%d,%d expecting %d,%d,%d",
											n, x, y, z,
											tileGroup.tiles[n].xTile,
											tileGroup.tiles[n].yTile,
											tileGroup.tiles[n].zTile)) end
	if not force
	and tileGroup.tiles[n].goodTile
	and x == tileGroup.tiles[n].xTile
	and y == tileGroup.tiles[n].yTile
	and z == tileGroup.tiles[n].zTile then
		return
	end

	if x < 0 or x >= 2^z or y < 0 or y >= 2^z or z < 0 or z > zoomMax then
		--local telapsed = (MOAISim.getDeviceTime()-tstart)*1000
		--print("osmLoadTile["..n..'] GRAY '..x..','..y..','..z.." "..string.format("%dmsec",telapsed))
		displayGrayTile(n)
		return
	end
if debugging then print(string.format("osmLoadTile:[%d]<-%d,%d,%d", n, x, y, z)) end
	tileGroup.tiles[n].xTile, tileGroup.tiles[n].yTile, tileGroup.tiles[n].zTile = x, y, z
	tileGroup.tiles[n].goodTile = false
	
	local tryImage = nil
	if true then	-- false to test Busy/stretch tiles
	tryImage = tilemgr:osmLoadTile(n,x,y,z,force,
function(gotImage)
local expected = n >= 1 and n <= #tileGroup.tiles and tileGroup.tiles[n].xTile == x and tileGroup.tiles[n].yTile == y and tileGroup.tiles[n].zTile == z
if expected then
	if gotImage then
		displayTileImage(n, gotImage, x, y, z)
		--local telapsed = (MOAISim.getDeviceTime()-tstart)*1000
		--print(string.format("got expected %d %d %d in %dmsec", x, y, z, telapsed))
	else
		displayTileFailed(n, x, y, z)
		--local telapsed = (MOAISim.getDeviceTime()-tstart)*1000
		--print(string.format("Expected FAILED %d %d %d in %dmsec", x, y, z, telapsed))
	end
else
	for t = 1, #tileGroup.tiles do
		local tile = tileGroup.tiles[t]
		if tile.xTile == x and tile.yTile == y and tile.zTile == z then
			print('osmPlanetListner['..n..'] LATE '..x..','..y..','..z..' wanted by '..t)
			if gotImage then
				displayTileImage(t, gotImage, x, y, z)
				--local telapsed = (MOAISim.getDeviceTime()-tstart)*1000
				--print(string.format("got UNexpected %d %d %d in %dmsec", x, y, z, telapsed))
			else
				displayTileFailed(t, x, y, z)
				--local telapsed = (MOAISim.getDeviceTime()-tstart)*1000
				--print(string.format("UNExpected FAILED %d %d %d in %dmsec", x, y, z, telapsed))
			end
		end
	end
end
end)
end

	if tryImage then
		--print('osmLoadTile:Recovered '..file)
		--if busyImage then busyImage:removeSelf(); busyImage = nil end
		displayTileImage(n, tryImage, x, y, z)
		--local telapsed = (MOAISim.getDeviceTime()-tstart)*1000
		--print(string.format("Displayed %d %d %d in %dmsec", x, y, z, telapsed))
		--print("Need to show256 from osmTiles:osmLoadTile()")
		--show256(file)
	--elseif osmLoading[n] then
		--print('osmLoadTile['..n..':BUSY!  Not Loading '..file)
	else
		--print('osmLoadTile:Remote Loading '..file)
		displayBusyTile(n, x,y,z)
		--local telapsed = (MOAISim.getDeviceTime()-tstart)*1000
		--print(string.format("Busy %d %d %d in %dmsec", x, y, z, telapsed))
	end
end

function osmTiles:osmLoadTiles(x,y,z,force)
	--osmTiles:setSize(Application.viewWidth, Application.viewHeight)	-- Just to make sure the screen shape hasn't changed!

	if force or not (tileGroup.actualX == x and tileGroup.actualY == y and tileGroup.actualZ == z) then
		local tstart = MOAISim.getDeviceTime()
		tileGroup.actualX, tileGroup.actualY, tileGroup.actualZ = x, y, z
		local xo, yo
		local reloaded = false
		x, xo = math.modf(x)
		y, yo = math.modf(y)
		if force or not (x == tileGroup.tiles[1].xTile and y == tileGroup.tiles[1].yTile and z == tileGroup.tiles[1].zTile) then
print("Reloading for "..x..','..y..','..z..' from '..tileGroup.tiles[1].xTile..','..tileGroup.tiles[1].yTile..','..tileGroup.tiles[1].zTile)
			tileGroup.tileVersion = newVersionID()
			tileGroup.wrapped = false
			reloaded = true
			tilemgr:flushPriorityQueue("osmReload")
			for n = 1, #tileGroup.tiles do
				local xt = x+tileGroup.tiles[n].xOffset
				local yt = y+tileGroup.tiles[n].yOffset
				while xt < 0 do tileGroup.wrapped = true xt = xt + 2^z end
				while xt >= 2^z do tileGroup.wrapped = true xt = xt - 2^z end
				osmLoadTile(n, xt, yt, z, force)
				--deferLoadTile(n, xt, yt, z)
				if n == 1 then
					tileGroup.minX, tileGroup.minY = xt, yt
					tileGroup.maxX, tileGroup.maxY = xt, yt
				else
					if xt < tileGroup.minX then tileGroup.minX = xt end
					if xt > tileGroup.maxX then tileGroup.maxX = xt end
					if yt < tileGroup.minY then tileGroup.minY = yt end
					if yt > tileGroup.maxY then tileGroup.maxY = yt end
				end
			end
			tileGroup.maxX = tileGroup.maxX + 1	-- For < comparison
			tileGroup.maxY = tileGroup.maxY + 1	-- For < comparison
			local z20 = (2^(20-zoom))
			tileGroup.minX20 = tileGroup.minX*z20	-- Move out to zoom 20 coords
			tileGroup.maxX20 = tileGroup.maxX*z20	-- Move out to zoom 20 coords
			tileGroup.minY20 = tileGroup.minY*z20	-- Move out to zoom 20 coords
			tileGroup.maxY20 = tileGroup.maxY*z20	-- Move out to zoom 20 coords
			local telapsed = (MOAISim.getDeviceTime()-tstart)*1000
print(string.format("osmTiles:osmLoadTiles:Loaded %.2f,%.2f-> %.2f,%.2f or %.2f,%.2f -> %.2f,%.2f in %dms",
					tileGroup.minX, tileGroup.minY,
					tileGroup.maxX, tileGroup.maxY,
					tileGroup.minX20, tileGroup.minY20,
					tileGroup.maxX20, tileGroup.maxY20,
					telapsed))
		end
		tileGroup.tilesGroup.xOffset = math.floor(tileSize/2-tileSize*xo)
		tileGroup.tilesGroup.yOffset = math.floor(tileSize/2-tileSize*yo)
		if (z == 0) then	-- Zoom zero doesn't offset
			tileGroup.tilesGroup.xOffset = 0
			tileGroup.tilesGroup.yOffset = 0
		end
		if reloaded
		or not tileGroup.tilesGroup.x or not tileGroup.tilesGroup.y
		or tileGroup.tilesGroup.x ~= tileGroup.tilesGroup.xOffset
		or tileGroup.tilesGroup.y ~= tileGroup.tilesGroup.yOffset then

			if reloaded then
print("osmTiles:osmLoadTiles:Offset RELOADED!")
			elseif not tileGroup.tilesGroup.x or not tileGroup.tilesGroup.y then
print("osmTiles:osmLoadTiles:Offset INITIALIZING!")
			else
				local xo=tileGroup.tilesGroup.x-tileGroup.tilesGroup.xOffset
				local yo=tileGroup.tilesGroup.y-tileGroup.tilesGroup.yOffset
--print(string.format("osmTiles:osmLoadTiles:Offset moved %.3f %.3f", xo, yo))
			end
			tileGroup.offsetVersion = newVersionID()
		end

		tileGroup.tilesGroup.x = tileGroup.tilesGroup.xOffset
		tileGroup.tilesGroup.y = tileGroup.tilesGroup.yOffset
		tileGroup.tilesGroup:setLoc(tileGroup.tilesGroup.x, tileGroup.tilesGroup.y)
		--timer.performWithDelay(20*tileGroup.tilesGroup:getNumChildren()/4+20, fixupSymbols)
		fixupSymbols("osmLoadTiles")
		--[[if tileGroup.symbolLabel then
			osmTiles:showSymbol(tileGroup.symbolLabel.lat, tileGroup.symbolLabel.lon, tileGroup.symbolLabel)
		end]]
	else
		print('Not moving tileGroup @ ', x, y, z)
	end
end

--	Clean up all the old-style file names that we are orphaning...
--[[do
	local fullpath = system.pathForFile( "", system.TemporaryDirectory )
	for file in lfs.dir(fullpath) do
		if string.match(file,"^%d-%-%d-%-%d-.png$") then
			-- print( "Found file: " .. file )
			local fullfile = system.pathForFile( file, system.TemporaryDirectory )
			os.remove(fullfile)
		else	print("NOT "..file)
		end
	end
end]]

function osmTiles:setOrientation(orientation)
	if orientation:sub(1,8) == 'portrait' then
		tileGroup.x = display.screenOriginX
		tileGroup.y = display.screenOriginY --+ display.topStatusBarContentHeight
		tileGroup.square.rotation = 0
		tileGroup.square.x = Application.viewWidth / 2
		tileGroup.square.y = Application.viewHeight / 2 + display.topStatusBarContentHeight/2
		--tileGroup.square:setFillColor(255,255,255)
		for n=1, #tileGroup.tiles do
			local xo, yo = tileGroup.tiles[n].xOffset, tileGroup.tiles[n].yOffset
			tileGroup.tiles[n].x = (Application.viewWidth - tileSize)/2 + tileSize*xo
			tileGroup.tiles[n].y = (Application.viewHeight - tileSize)/2 + tileSize*yo + display.topStatusBarContentHeight/2
		end
		tileGroup.zoomGroup.alphaSlider.x = Application.viewWidth / 2
		tileGroup.zoomGroup.alphaSlider.y = Application.viewHeight - tileGroup.zoomGroup.alphaSlider.contentHeight/2
		tileGroup.zoomGroup.zoomSlider.x = tileGroup.zoomGroup.zoomSlider.contentWidth/2
		tileGroup.zoomGroup.zoomSlider.y = Application.viewHeight - 256 + tileGroup.zoomGroup.zoomSlider.contentHeight/2 + (256-tileGroup.zoomGroup.zoomSlider.contentHeight)/2
		showSliderText(tileGroup.zoomGroup.alphaSlider)
		showSliderText(tileGroup.zoomGroup.zoomSlider)
		tileGroup.zoomGroup.bwControl.x = tileGroup.zoomGroup.zoomSlider.contentWidth + tileGroup.zoomGroup.bwControl.contentWidth/2
		tileGroup.zoomGroup.bwControl.y = tileGroup.zoomGroup.alphaSlider.y - tileGroup.zoomGroup.alphaSlider.contentHeight/2 - tileGroup.zoomGroup.bwControl.contentHeight/2
		timer.performWithDelay(0,fixTileGroupSegments)
		fixupSymbols("setOrientation")
	elseif orientation:sub(1,9) == 'landscape' then
		tileGroup.x = display.screenOriginX
		tileGroup.y = display.screenOriginY --+ display.topStatusBarContentHeight
		tileGroup.square.rotation = 90
		tileGroup.square.x = Application.viewHeight / 2
		tileGroup.square.y = Application.viewWidth / 2 + display.topStatusBarContentHeight/2
		--tileGroup.square:setFillColor(0,0,0)
		-- tileGroup.y = Application.viewWidth/2 - tileGroup.contentHeight/2
		-- tileGroup.x = display.screenOriginX + Application.viewHeight - tileGroup.contentWidth
		for n=1, #tileGroup.tiles do
			local xo, yo = tileGroup.tiles[n].xOffset, tileGroup.tiles[n].yOffset
			tileGroup.tiles[n].x = (Application.viewHeight - tileSize)/2 + tileSize*xo
			tileGroup.tiles[n].y = (Application.viewWidth - tileSize)/2 + tileSize*yo + display.topStatusBarContentHeight/2
			tileGroup.tiles[n]:setLoc(tileGroup.tiles[n].x, tileGroup.tiles[n].y)
		end
		tileGroup.zoomGroup.alphaSlider.x = Application.viewWidth / 2
		tileGroup.zoomGroup.alphaSlider.y = Application.viewWidth - tileGroup.zoomGroup.alphaSlider.contentHeight/2
		tileGroup.zoomGroup.zoomSlider.x = tileGroup.zoomGroup.zoomSlider.contentWidth/2
		tileGroup.zoomGroup.zoomSlider.y = Application.viewWidth - 256 + tileGroup.zoomGroup.zoomSlider.contentHeight/2 + (256-tileGroup.zoomGroup.zoomSlider.contentHeight)/2
		tileGroup.zoomGroup.zoomSlider.y = Application.viewWidth / 2
		showSliderText(tileGroup.zoomGroup.alphaSlider)
		showSliderText(tileGroup.zoomGroup.zoomSlider)
		tileGroup.zoomGroup.bwControl.x = tileGroup.zoomGroup.zoomSlider.contentWidth + tileGroup.zoomGroup.bwControl.contentWidth/2
		tileGroup.zoomGroup.bwControl.y = tileGroup.zoomGroup.alphaSlider.y - tileGroup.zoomGroup.alphaSlider.contentHeight/2 - tileGroup.zoomGroup.bwControl.contentHeight/2
		timer.performWithDelay(0,fixTileGroupSegments)
		fixupSymbols("setOrientation")
	end
end

function osmTiles:insertUnderMap(group)
	tileGroup:insert(2,group)
end

function osmTiles:insertOverMap(group)
	tileGroup:insert(group)
end

function osmTiles:removeControl(newGroup)
	local myGroup = tileGroup.zoomGroup
	if myGroup.segments then
		for k,v in pairs(myGroup.segments) do
			if v == newGroup then myGroup.segments[k] = nil end
		end
	end
end

function osmTiles:insertControl(newGroup, isSegmented)
	local myGroup = tileGroup.zoomGroup
	if isSegmented then
		if not myGroup.segments then myGroup.segments = {} end
		table.insert(myGroup.segments, newGroup)
		newGroup.alpha = myGroup.alpha
	else myGroup:insert(newGroup)
	end
end

local function onSegmentPress( event )
   local target = event.target
   --print( "Segment Label is:", target.segmentLabel )
   --print( "Segment Number is:", target.segmentNumber )
   if target.segmentNumber == 1 then	-- Dim
		config.lastDim = true
		tileGroup:setClearColor ( 0,0,0,1 )
		--tileGroup.square:setFillColor(0,0,0,255)	-- Make the gray square turn black
	elseif target.segmentNumber == 2 then	-- Bright
		config.lastDim = false
		tileGroup:setClearColor ( 1,1,1,1 )
		--tileGroup.square:setFillColor(255,255,255,255)	-- Make the gray square turn white
	end
end

function osmTiles:getSize()
	return tileGroup.width, tileGroup.height
end

function osmTiles:resetSize(why)
	local width, height = osmTiles:getSize()
	osmTiles:removeCrosshair()
	tileGroup.sizeVersion = newVersionID()
	
	if tileGroup.tiles then
		print('osmTiles:setSize:clearing '..#tileGroup.tiles..' tiles and '..tileGroup.tilesGroup:getNumChildren()..' in group')
		do i=1,#tileGroup.tiles
			tileGroup.tiles[i]:removeChildren()	-- Remove all images
		end
		tileGroup.tilesGroup:removeChildren()	-- and empty the tile layer
	end
	tileGroup.tiles = {}	-- array of tiles covering visual surface
local function addTilePane(xo,yo)
	local n = #tileGroup.tiles + 1
	tileGroup.tiles[n] = Group()	-- One of the visual surface tiles
	tileGroup.tilesGroup:addChild(tileGroup.tiles[n])
	tileGroup.tiles[n].x = (width - tileSize)/2 + tileSize*xo
	tileGroup.tiles[n].y = (height - tileSize)/2 + tileSize*yo
	tileGroup.tiles[n].xOffset, tileGroup.tiles[n].yOffset = xo, yo
	tileGroup.tiles[n]:setLoc(tileGroup.tiles[n].x, tileGroup.tiles[n].y)
	tileGroup.tiles[n]:setScl(tileScale,tileScale,1)
if debugging then print(string.format("addTilePane:[%d]<-%d,%d,%d", n, -1,-1,-1)) end
	tileGroup.tiles[n].xTile, tileGroup.tiles[n].yTile, tileGroup.tiles[n].zTile = -1, -1, -1
end
--[[
	addTilePane(0,0)
	addTilePane(-1,0) addTilePane(1,0) addTilePane(0,-1) addTilePane(0,1)
	addTilePane(-1,-1) addTilePane(-1,1) addTilePane(1,-1) addTilePane(1,1)
	addTilePane(-2,0) addTilePane(2,0) addTilePane(0,-2) addTilePane(0,2)
	addTilePane(-2,-1) addTilePane(-1,-2) addTilePane(1,-2) addTilePane(2,-1)
	addTilePane(-2,1) addTilePane(2,1) addTilePane(-1,2) addTilePane(1,2)
]]
	local xc = math.floor(width/tileSize/2)+1
	local yc = math.floor(height/tileSize/2)+1
	print('osmTiles:setSize:'..width..'x'..height..' needs '..(xc*2+1)..'x'..(yc*2+1)..' tiles')
	addTilePane(0,0)	-- Always put this one first!
	if true then
		local x = -xc
		while (x <= xc) do
			local y = -yc
			while (y <= yc) do
				if x ~= 0 or y ~= 0 then
					--print('osmTiles:addTilePane['..x..','..y..']')
					addTilePane(x,y)
				end
				y = y + 1
			end
			x = x + 1
		end
	end
	print('osmTiles:setSize:Created '..#tileGroup.tiles..' tiles to cover '..width..'x'..height)
	table.sort(tileGroup.tiles, function(a,b)
								if a.xOffset == 0 and a.yOffset == 0 then return true end	-- 0,0 is first
								if b.xOffset == 0 and b.yOffset == 0 then return false end	-- 0,0 is first
								local da = math.sqrt(a.xOffset*a.xOffset+a.yOffset*a.yOffset)
								local db = math.sqrt(b.xOffset*b.xOffset+b.yOffset*b.yOffset)
								return da<db	-- closer to origin is first
							end)
	local x, y, z = tileGroup.actualX, tileGroup.actualY, tileGroup.actualZ
	tileGroup.actualX, tileGroup.actualY, tileGroup.actualZ = -1, -1, -1
	if x and y and z then osmTiles:osmLoadTiles(x,y,z) invokeCallbacks(why) end
	
--[[
	local points = {}
	for i = 0, 100 do
		points[#points+1] = i*width/100
		points[#points+1] = i*height/100
	end
]]
end

function osmTiles:setSize(width, height)
	if tileGroup.width == width and tileGroup.height == height then return end
	tileGroup.width, tileGroup.height = width, height
	osmTiles:resetSize('size')
end

function osmTiles:start()
	tileGroup.tilesGroup = Group()	-- for easy alpha setting
	tileGroup.tilesGroup.alpha = tileAlpha		-- Initial value

	osmTiles:setSize(Application.viewWidth, Application.viewHeight)
	
	tileGroup.x = 0 --display.screenOriginX
	tileGroup.y = 0 --display.screenOriginY
	tileGroup:addEventListener( "tap", tileTap )
	tileGroup:addEventListener( "touch", tileTouch )
	
	tileGroup.scale = 2
	--tileGroup:setScl(tileGroup.scale, tileGroup.scale, 1)

	--tileGroup.xScale = 0.8
	--tileGroup.yScale = 0.8

--[[
	local leftSquare = Graphics {width = Application.viewWidth/2, height = Application.viewHeight, left = 0, top = 0}
    leftSquare:setPenColor(0.25, 0.25, 0.25, 1):fillRect()	-- dark on the left
	tileGroup:addChild(leftSquare)
	local rightSquare = Graphics {width = Application.viewWidth/2, height = Application.viewHeight, left = Application.viewWidth/2, top = 0}
    rightSquare:setPenColor(0.75, 0.75, 0.75, 1):fillRect()	-- light on the right
	tileGroup:addChild(rightSquare)
]]

--print(string.format('tileGroup@%i,%i size %ix%i', tileGroup.x, tileGroup.y, tileGroup.contentWidth, tileGroup.contentHeight))

--[[
	tileGroup.square = display.newRect( 0, 0, Application.viewWidth, Application.viewHeight)
	tileGroup:insert(1,tileGroup.square)
	--tileGroup.square.x = (Application.viewWidth-display.screenOriginX)/2
	--tileGroup.square.y = (Application.viewHeight-display.screenOriginY)/2
	--tileGroup.square:setFillColor(255,255,255,255)	-- Make the gray square turn white
	if config.lastDim then	-- Dim
		tileGroup.square:setFillColor(0,0,0,255)	-- Make the gray square turn black
	else	-- Bright
		tileGroup.square:setFillColor(255,255,255,255)	-- Make the gray square turn white
	end
	--tileGroup.square.strokeWidth = 2
	--tileGroup.square:setStrokeColor(255,255,0,127)
]]
--[[
	if config.lastDim then	-- Dim
		tileGroup:setClearColor ( 0,0,0,1 )	-- Black background
	else	-- Bright
		tileGroup:setClearColor ( 1,1,1,1 )	-- White background
	end
]]
	tileGroup:addChild(tileGroup.tilesGroup)	 -- Just above the white "square"
	
	tileGroup.zoomGroup = Group()

--[[
	tileGroup.zoomGroup.alphaSlider = widget.newSlider
														{
														   orientation = "horizontal",
														   width = 200,
														   left = 56/2,
														   top = 128,
														   listener = alphaSliderListener
														}
	tileGroup.zoomGroup:insert(tileGroup.zoomGroup.alphaSlider)
	tileGroup.zoomGroup.alphaSlider.x = Application.viewWidth / 2
	tileGroup.zoomGroup.alphaSlider.y = Application.viewHeight - tileGroup.zoomGroup.alphaSlider.contentHeight/2
	tileGroup.zoomGroup.alphaSlider:setValue(math.floor(tileAlpha*100))
	showAlpha(tileAlpha)
	
	tileGroup.zoomGroup.zoomSlider = widget.newSlider
														{
														   orientation = "vertical",
														   height = 200,
														   left = 0,
														   top = 56/2,
														   listener = zoomSliderListener
														}
	tileGroup.zoomGroup:insert(tileGroup.zoomGroup.zoomSlider)
	tileGroup.zoomGroup.zoomSlider.x = tileGroup.zoomGroup.zoomSlider.contentWidth/2
	tileGroup.zoomGroup.zoomSlider.y = Application.viewHeight - 256 + tileGroup.zoomGroup.zoomSlider.contentHeight/2 + (256-tileGroup.zoomGroup.zoomSlider.contentHeight)/2
	tileGroup.zoomGroup.zoomSlider:setValue(math.floor(zoom/18*100+0.5))
	showZoom(zoom)

	tileGroup:insert(tileGroup.zoomGroup)
	tileGroup.zoomGroup.alpha = 0	-- Don't want to see it initially

local defaultSegment = 2	-- Bright
if config.lastDim then defaultSegment = 1 end	-- Dim

tileGroup.zoomGroup.bwControl = widget.newSegmentedControl
{
   left = 65,
   top = 110,
   segments = { "Dim", "Bright" },
   segmentWidth = 50,
   defaultSegment = defaultSegment,
   onPress = onSegmentPress
}
osmTiles:insertControl(tileGroup.zoomGroup.bwControl, true)
--]]

end

return osmTiles
