-- tilemgr:osmLoadTile(n,x,y,z,force,callback)
module (..., package.seeall)

local toast = require("toast");

local stations = require('stationList')
local osmTiles = require("osmTiles")	-- This currently sets the Z order of the map
local tilemgr = require("tilemgr")

local buttonAlpha = 0.8

local myWidth, myHeight

local updateRoutine, center, symbol, dot, dotvisible, dot2, dot2visible
local worldOverlay, worldOverlay2, mapBackground2
local groupLabel, groupLabel2


local coGlobals

local function MonitorGlobals()
	local known = {}
	for k,v in pairs(_G) do
		--print(string.format("MonitorGlobals:%s(%s)", type(v), k))
		known[k] = type(v)
	end
	print("MonitorGlobals:Monitoring Globals")
	while coGlobals do
		for k,v in pairs(_G) do
			if not known[k] or known[k] ~= type(v) then
				known[k] = type(v)
				print(string.format("MonitorGlobals:New Global:%s(%s)", known[k], k))
			elseif known[k] ~= type(v) then
				print(string.format("MonitorGlobals:Global:%s(%s) is now %s", known[k], k, type(v)))
				known[k] = type(v)
			end
		end
		coroutine.yield()
	end
	print("MonitorGlobals:Monitor Exiting")
end

local function closeScene()
	local current = SceneManager:getCurrentScene()
	local name = current:getName()
	if name == "maps_scene" then
		SceneManager:closeScene({animation="popOut"})
	else print("maps_scene:NOT Closing "..tostring(name))
	end
end

local function latlonToMap2(lat, lon, zoom)
	local x, y = tilemgr:osmTileNum(lat, lon, zoom)
	x = x - math.floor(mapBackground2.xt)
	y = y - math.floor(mapBackground2.yt)
	x, y = x*256, y*256
--	print(string.format("Lat:%.4f Lon:%.4f is Pixel X:%.4f Y:%.4f at zoom:%d", lat, lon, x20, y20, zoom))
	return x, y
end

local function latlonToMap0(lat, lon)
	local x20, y20 = tilemgr:osmTileNum(lat, lon, 20)
	x20, y20 = x20 / 2^20*256, y20 / 2^20*256
--	print(string.format("Lat:%.4f Lon:%.4f is Pixel X:%.4f Y:%.4f at zoom:%d", lat, lon, x20, y20, 20))
	return x20, y20
end

local function latlonToXY(lat, lon, zoom)
	zoom = zoom or 0
	local x20, y20 = tilemgr:osmTileNum(lat, lon, zoom)
	--x20, y20 = x20 / 2^(20-zoom), y20 / 2^(20-zoom)
--	print(string.format("Lat:%.4f Lon:%.4f is Tile X:%.4f Y:%.4f at zoom:%d", lat, lon, x20, y20, zoom))
	return x20, y20
end

local function refreshOverlay()
	print("refreshing overlay")
	groupLabel:setText("Refreshing...")
	worldOverlay:setTexture(tilemgr:getContentImage(osmTiles:getZoom(), groupLabel))
end

local function setTargetSize()
	local target = group1:getChildByName("target")
	if target then
		local scale = mapGroup:getScl()
		local zd = 2^mapBackground2.zt
		local size = 256/zd
		target:setSize(size,size)
		if size*scale < 64*config.Screen.scale then
			target:setScl(64*config.Screen.scale/(size*scale))
		else
			target:setScl(1)
		end
	end
end

local function setTarget(xt,yt,zt)
	local target = group1:getChildByName("target")
	if target then
		setTargetSize()
		local pow2 = 2^zt
		local xp, yp = math.floor(xt)/pow2, math.floor(yt)/pow2
		target:setPos(xp*256,yp*256)
	else
		print("No TARGET to move!")
	end
end

local function setBackground2(image, xt, yt, zt)
	print(string.format("setBackground2 from %s to %s, %d children in group2", tostring(mapBackground2), tostring(image), #group2:getChildren()))
	if image then
		group2:removeChild(mapBackground2)
		mapBackground2 = image
		mapBackground2:setPriority(1)
		mapBackground2:setAlpha(0.5)
		group2:addChild(mapBackground2)
		mapBackground2.xt, mapBackground2.yt, mapBackground2.zt = xt, yt, zt
	end
	setTarget(xt,yt,zt)
end

local function newBackground2(image, xt, yt, zt)
	if image then
		print(string.format("newBackground2:%s from %d %d %d now %d %d %d", tostring(image), xt, yt, zt,
							mapBackground2.xt, mapBackground2.yt, mapBackground2.zt))
		if mapBackground2.xt == xt and mapBackground2.yt == yt and mapBackground2.zt == zt then
			setBackground2(image, xt, yt, zt)
		end
	else
		print(string.format("newBackground2:FAILED(%s) from %d %d %d now %d %d %d", tostring(image), xt, yt, zt,
							mapBackground2.xt, mapBackground2.yt, mapBackground2.zt))
	end
end

local function refreshOverlay2()
    print("refreshing overlay2")

	local z = osmTiles:getZoom()
	local zd = z<8 and z or 8
--	local clat, clong = osmTiles:getCenter()
--	local xd, yd = latlonToXY(clat,clong,z)
	local pow2 = 2^(mapBackground2.zt-z)
	local xd, yd = mapBackground2.xt/pow2, mapBackground2.yt/pow2
	print(string.format("refreshOverlay2:%f %f %f becomes %f %f %f via %f", mapBackground2.xt, mapBackground2.yt, mapBackground2.zt, xd, yd, (z-zd), pow2))
	-- local xt, yt, zt = math.floor(xd/2^zd), math.floor(yd/2^zd), z-zd
	local xt, yt, zt = xd/2^zd, yd/2^zd, z-zd
	--local xt, yt, zt = xd, yd, z-zd
	--local image, stretch = tilemgr:getTileImageOrStretch(math.floor(xt),math/floor(yt),zt, function (new) newBackground2(new, xt, yt, zt) end)
--[[
	local z = osmTiles:getZoom()
	local xc, yc = osmTiles:getCenter()
	local xd, yd = latlonToXY(xc,yc,z)
	local zd = z<8 and z or 8
	--local xt, yt, zt = math.floor(xd/2^zd), math.floor(yd/2^zd), z-zd
	local xt, yt, zt = xd/2^zd, yd/2^zd, z-zd
]]
	print(string.format("refreshOverlay2:%f %f %f becomes %f %f %f", mapBackground2.xt, mapBackground2.yt, mapBackground2.zt, xt, yt, zt))
	local image, stretch = tilemgr:getTileImageOrStretch(math.floor(xt),math.floor(yt),zt, function (new) newBackground2(new, xt, yt, zt) end)
	setBackground2(image, xt, yt, zt)
	groupLabel2:setText("Refreshing...")
	worldOverlay2:setTexture(tilemgr:getContentImage2(xd,yd,z, groupLabel2))
end

local function refreshOverlays()
	refreshOverlay()
	refreshOverlay2()
end

local function moveAndScaleMapGroup(width, height)
	print(string.format("getContentImage:Moving mapGroup=%s", tostring(mapGroup)))
	local scale = 1
	if width > height then
		group1:setLoc(-130,0)
		group2:setLoc(130,0)
		local tscale = math.min(width/512,height/256)
		if tscale > 1 then tscale = math.floor(tscale) end
		scale = tscale
	else
		group1:setLoc(0,-130)
		group2:setLoc(0,130)
		local tscale = math.min(width/256,height/512)
		if tscale > 1 then tscale = math.floor(tscale) end
		scale = tscale
	end
	mapGroup:setScl(scale)
	setTargetSize()
	if symbol then symbol:setScl(1/scale) end
	if dot then dot:setScl(1/scale) end
	if dot2 then dot2:setScl(1/scale) end
	mapGroup:setLoc(width/2-256*mapGroup:getScl()/2,(height-titleBackground:getHeight())/2-256*mapGroup:getScl()/2+titleBackground:getHeight())
end

local function reCreateButtons(width,height)
	if buttonView then buttonView:setScene(nil) buttonView:setLayer(nil) buttonView:dispose() end
	
    buttonView = View {
        scene = scene,
		priority = 2000000000,
    }

    purgeButton = Button {
        text = "Purge",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66}, priority=2000000000,
        parent = buttonView, priority=2000000000,
		onClick = function()
						toast.new('Tap here to DELETE all tiles', 2000,
									function()
										local count, err = tilemgr:deleteAllTiles()
										if count then
											toast.new(string.format("Purged %d Tiles", count))
										else
											toast.new("Purge failed with "..tostring(err))
										end
									end)
					end,
    }
	purgeButton:setScl(config.Screen.scale,config.Screen.scale,1)

    inButton = Button {
        text = "+", textSize = 32,
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {50, 66},
        parent = buttonView, priority=2000000000,
        onClick = function() osmTiles:deltaZoom(1) refreshOverlays() end,
    }
	inButton:setScl(config.Screen.scale,config.Screen.scale,1)
    in3Button = Button {
        text = "+++", textSize = 16,
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {50, 66},
        parent = buttonView, priority=2000000000,
        onClick = function() osmTiles:deltaZoom(3) refreshOverlays() end,
    }
	in3Button:setScl(config.Screen.scale,config.Screen.scale,1)
    outButton = Button {
        text = "-", textSize = 32,
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {50, 66},
        parent = buttonView, priority=2000000000,
        onClick = function() osmTiles:deltaZoom(-1) refreshOverlays() end,
    }
	outButton:setScl(config.Screen.scale,config.Screen.scale,1)
    out3Button = Button {
        text = "- - -", textSize = 20,
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {50, 66},
        parent = buttonView, priority=2000000000,
        onClick = function() osmTiles:deltaZoom(-3) refreshOverlays() end,
    }
	out3Button:setScl(config.Screen.scale,config.Screen.scale,1)
    oneButton = Button {
        text = "One",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66},
        parent = buttonView, priority=2000000000,
        onClick = function()
					local zoom, zoomMax = osmTiles:getZoom()
						osmTiles:zoomTo(zoomMax) refreshOverlays()
						stations:updateCenterStation()	-- re-center on current center
					end,
    }
	oneButton:setScl(config.Screen.scale,config.Screen.scale,1)
    allButton = Button {
        text = "All",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66},
        parent = buttonView, priority=2000000000,
        onClick = function()
--[[
						local xs = myWidth / 256
						local ys = myHeight / 256
						osmTiles:zoomTo(math.min(xs,ys))
]]
						osmTiles:showAll()
						refreshOverlays() 
					end,
    }
	allButton:setScl(config.Screen.scale,config.Screen.scale,1)

    purgeButton:setLeft(10) purgeButton:setBottom(height-10)

    in3Button:setRight(width-10) in3Button:setBottom(height-10)
    inButton:setRight(in3Button:getLeft()) inButton:setBottom(height-10)
    outButton:setRight(inButton:getLeft()) outButton:setBottom(height-10)
    out3Button:setRight(outButton:getLeft()) out3Button:setBottom(height-10)

    oneButton:setRight(width-10) oneButton:setBottom(inButton:getTop()-10)
    allButton:setRight(oneButton:getLeft()) allButton:setBottom(outButton:getTop()-10)
end

local function resizeHandler ( width, height )
	myWidth, myHeight = width, height

	print('maps_scene:onResize:'..tostring(width)..'x'..tostring(height))

	local butScene = SceneManager:findSceneByName("buttons_scene")
	if butScene and type(butScene.resizeHandler) == 'function' then
		butScene.resizeHandler(width, height)
		local POPUP_LAYER = "SceneAnimationPopUpLayer"
		local layer = butScene:getChildByName(POPUP_LAYER)
		if layer then
			print("maps_scene:found layer:"..tostring(layer).." "..tostring(layer.getChildCount))
			if type(layer.getChildCount) == "function" then
				print("Layer has "..tostring(layer:getChildCount()).." children")
			end
			local w, h = layer:getSize()
			print("maps_scene:setting layer size from "..tostring(w).."x"..tostring(h).." to "..tostring(width).."x"..tostring(height))
			layer:setSize(width,height)
			if (layer.g) then
				local w, h = layer.g:getSize()
				print("maps_scene:setting layer g size from "..tostring(w).."x"..tostring(h).." to "..tostring(width).."x"..tostring(height))
				layer.g:setSize(width,height)
			end
		end
	else
		print("Could not locate buttons_scene, going for APRSmap")
		local mapScene = SceneManager:findSceneByName("APRSmap")
		if mapScene and type(mapScene.resizeHandler) == 'function' then
			mapScene.resizeHandler(width, height)
		end
	end

	layer:setSize(width,height)
	reCreateButtons(width,height)
	
	titleBackground:setSize(width, 40*config.Screen.scale)
	local x,y = titleText:getSize()
	titleText:setLoc(width/2, 25*config.Screen.scale)

	if mapGroup then
		moveAndScaleMapGroup(width, height)
	end
end

function onStart()
    print("Maps:onStart()")
	
	MOAICoroutine.new():run(function()
							local timer = MOAITimer.new()
							timer:setSpan(200/1000)
							--while center and dot do
							local anim, anim2
							while dot do
								--if center ~= stations:getCenterStation() then
								--	mapGroup:removeChild(symbol)
								--	center = stations:getCenterStation()
								--	symbol = getSymbolImage(center.symbol, center.stationID)
								--	mapGroup:addChild(symbol)
								--end
								--local xo, yo = symbol:getLoc()
								--local xc, yc = latlonToMap0(center.lat, center.lon)
								--if xo ~= xc or yo ~= yc then
									--symbol:seekLoc(xc,yc,0,15)
								--	symbol:setLoc(xc,yc)
								--end
								local s = mapGroup:getScl()
								local xc, yc = dot:getLoc()
								local xd, yd = latlonToMap0(osmTiles:getCenter())
								xd = xd
								if math.abs(xd-xc) >= 1 or math.abs(yd-yc) >= 1 then
									if not dotvisible then
										mapGroup:addChild(dot)
										dotvisible = true
									end
									if not anim then
										--dot:setLoc(xd,yd)
										print(string.format("Animating from %.2f %.2f to %.2f %.2f delta %f %f scale %f", xc, yc, xd, yd, xd-xc, yd-yc, s))
										local dScale = dot:getScl()
										--dot:setScl(3*dScale)
										anim = Animation():parallel(
																Animation(dot, 2):seekLoc(xd,yd),
																Animation():sequence(
																	Animation(dot,1):seekScl(dScale*3,dScale*3),
																	Animation(dot,1):seekScl(dScale,dScale)))
										anim:play( { onComplete = function() anim = nil end } )
									end
								--elseif dotvisible then
								--	mapGroup:removeChild(dot)
								--	dotvisible = false
								end


--[[
								local z = osmTiles:getZoom()
								local xc, yc = osmTiles:getCenter()
								local xd, yd = latlonToXY(xc,yc,z)
								local zd = z<8 and z or 8
								local xt, yt, zt = math.floor(xd/2^zd), math.floor(yd/2^zd), z-zd
								if mapBackground2.xt ~= xt or mapBackground2.yt ~= yt or mapBackground2.zt ~= zt then
print(string.format("Map2 moved from %f %f %f to %f %f %f", mapBackground2.xt, mapBackground2.yt, mapBackground2.zt, xt, yt, zt))
									refreshOverlay2()
								end
]]

								local xc, yc = dot2:getLoc()
								local clat, clon = osmTiles:getCenter()
								local xd, yd = latlonToMap2(clat, clon, mapBackground2.zt)
								xd = xd
								if xd < 0 or xd > 255 or yd < 0 or yd > 255 then
									if dotvisible then
										group2:removeChild(dot2)
										dot2visible = false
										dot2:setLoc(128,128)
									end
								else
									if not dot2visible then
										group2:addChild(dot2)
										dot2visible = true
									end
									if math.abs(xd-xc) >= 1 or math.abs(yd-yc) >= 1 then
										if not anim2 then
											--dot:setLoc(xd,yd)
											print(string.format("Animating from %.2f %.2f to %.2f %.2f delta %f %f scale %f", xc, yc, xd, yd, xd-xc, yd-yc, s))
											local dScale = dot2:getScl()
											--dot:setScl(3*dScale)
											anim2 = Animation():parallel(
																	Animation(dot2, 2):seekLoc(xd,yd),
																	Animation():sequence(
																		Animation(dot2,1):seekScl(dScale*3,dScale*3),
																		Animation(dot2,1):seekScl(dScale,dScale)))
											anim2:play( { onComplete = function() anim2 = nil end } )
										end
									end
								end

								MOAICoroutine.blockOnAction(timer:start())
							end
							print("mapUpdater Stopping...")
						end)
end

function onResume()
    print("Maps:onResume()")
	if Application.viewWidth ~= myWidth or Application.viewHeight ~= myHeight then
		print("Maps:onResume():Resizing...")
		resizeHandler(Application.viewWidth, Application.viewHeight)
	end
end

function onPause()
    print("Maps:onPause()")
end

function onStop()
    print("Maps:onStop()")
	center, dot, dot2 = nil, nil, nil	-- Flag update routine to stop
end

function onDestroy()
    print("Maps:onDestroy()")
	coGlobals = nil
end

function onEnterFrame()
    --print("onEnterFrame()")
end

function onKeyDown(event)
    print("Maps:onKeyDown(event)")
	if event.key then
		print("processing key "..tostring(event.key))
		if event.key == 615 or event.key == 296 then	-- Down, zoom out
			osmTiles:deltaZoom(-1)  refreshOverlays()
		elseif event.key == 613 or event.key == 294 then	-- Up, zoom in
			osmTiles:deltaZoom(1)  refreshOverlays()
		elseif event.key == 609 or event.key == 290 then	-- Page Down, zoom out
			osmTiles:deltaZoom(-3)
		elseif event.key == 608 or event.key == 289 then	-- Page Up, zoom in
			osmTiles:deltaZoom(3)
		elseif event.key == 612 or event.key == 293 then	-- Left, fade out
			osmTiles:deltaTileAlpha(-0.1)  refreshOverlays()
		elseif event.key == 614 or event.key == 295 then	-- Right, fade in
			osmTiles:deltaTileAlpha(0.1)  refreshOverlays()
		end
		if event.key == 283 then	-- Escape
			closeScene()
		end
	end
end

function onKeyUp(event)
    print("Maps:onKeyUp(event)")
end

local touchDowns = {}

function onTouchDown(event)
	local wx, wy = layer:wndToWorld(event.x, event.y, 0)
--    print("Maps:onTouchDown(event)@"..tostring(wx)..','..tostring(wy)..printableTable(' onTouchDown', event))
	touchDowns[event.idx] = {x=event.x, y=event.y}
end

function onTouchUp(event)
	local wx, wy = layer:wndToWorld(event.x, event.y, 0)
--    print("Maps:onTouchUp(event)@"..tostring(wx)..','..tostring(wy)..printableTable(' onTouchUp', event))
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
--    SceneManager:closeScene({animation = "popOut"})
end

function onTouchMove(event)
    --print("Maps:onTouchMove(event)")
	if touchDowns[event.idx] then
		local dx = event.x - touchDowns[event.idx].x
		local dy = event.y - touchDowns[event.idx].y
		--print(string.format('Maps:onTouchMove:dx=%i dy=%i moveX=%i moveY=%i',
		--					dx, dy, event.moveX, event.moveY))
		osmTiles:deltaMove(event.moveX, event.moveY)
	end
end

function onCreate(e)

	coGlobals = MOAICoroutine.new()
	coGlobals:run(MonitorGlobals)

	print('Maps:onCreate, resizeHandler='..tostring(resizeHandler))
	local width, height = Application.viewWidth, Application.viewHeight
	myWidth, myHeight = width, height

	scene.resizeHandler = resizeHandler
	scene.backHandler = closeScene
	scene.menuHandler = closeScene

    layer = Layer {scene = scene, touchEnabled = true }
	--layer:setClearColor( 0,0,0,1 )	-- Black background
	
	reCreateButtons(width,height)
	
	titleGroup = Group { layer=layer }
	titleGroup:setLayer(layer)

	titleBackground = Graphics {width = width, height = 40*config.Screen.scale, left = 0, top = 0}
    titleBackground:setPenColor(0.25, 0.25, 0.25, 0.75):fillRect()	-- dark gray like Android
	titleBackground:setPriority(2000000000)
	titleGroup:addChild(titleBackground)
	
--[[
	fontImage = FontManager:getRecentImage()
	if fontImage then
		print("FontImage is "..tostring(fontImage))
		local sprite = Sprite{texture=fontImage, layer=layer}
		sprite:setPos((width-sprite:getWidth())/2, (height-sprite:getHeight())/2)
	end
]]

	titleText = TextLabel { text=tostring(MOAIEnvironment.appDisplayName)..' '..tostring(MOAIEnvironment.appVersion), textSize=28*config.Screen.scale }
	titleText:fitSize()
	titleText:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	titleText:setLoc(width/2, 20*config.Screen.scale)
	titleText:setPriority(2000000001)
	titleGroup:addChild(titleText)

	titleGroup:addEventListener("touchUp",
			function()
				print("Tapped Button:TitleGroup")
				closeScene()
			end)

			
	mapGroup = Group { layer=layer }
	mapGroup:setLayer(layer)
	
	group1 = Group { layer=layer }
	group1:setLayer(layer)
	group2 = Group { layer=layer }
	group2:setLayer(layer)
	mapGroup:addChild(group1)
	mapGroup:addChild(group2)

	local textColor = {0,0,0,1}
	groupLabel = TextBackground { text="This is the label", layer=layer, textSize=14 } --*config.Screen.scale
	groupLabel:setColor(unpack(textColor))
	groupLabel:fitSize()
	groupLabel:setAlignment ( MOAITextBox.CENTER_JUSTIFY, MOAITextBox.CENTER_JUSTIFY )
	--groupLabel:setLoc(groupLabel:getWidth()/2+config.Screen.scale, height-groupLabel:getHeight()/2)
	groupLabel:setLoc(128,groupLabel:getHeight()/2)
	groupLabel:setPriority(2000000000)
	group1:addChild(groupLabel)

	local mapBackground = Sprite {texture="0-0-0.png" }
	mapBackground:setPos(0,0)
	group1:addChild(mapBackground)
    worldOverlay = Sprite {texture = tilemgr:getContentImage(osmTiles:getZoom(), groupLabel), layer = layer, left = -130, top = (height-256)/2}
	worldOverlay:setPos(0,0)
	worldOverlay:setAlpha(0.5)
	worldOverlay:addEventListener("touchUp", function(e)
										print(printableTable("MapTap",e))
										if e.isTap then
										local scale = mapGroup:getScl()
local wx, wy = layer:wndToWorld(e.x, e.y, 0)										
--local wx, wy = worldOverlay:getPos()
local gx, gy = group1:getPos()
local mx, my = mapGroup:getPos()
local tx, ty = e.x/scale-mx/scale-gx, e.y/scale-my/scale-gy
--Port(Syslog):2020-04-29T01:31:56 Table[MapTap] = __index=table: 0x7b1405fb00 callback=function: 0x7b0d2ac000 idx=0 isTap=true moveX=-2 moveY=-1 oldX=793 oldY=563 screenX=793 screenY=563 stoped=false tapCount=1 tapTime=0.042 target=0x7b0c434038 <MOAIGraphicsProp> touchingProp=0x7b0c434038 <MOAIGraphicsProp> type=touchUp x=793 y=563 maps_scene.lua:573
--Port(Syslog):2020-04-29T01:31:56 worldOverlay @ 0,0 group1 @ 0,-130 mapGroup @ 156,580 TAP @ 637,113 maps_scene.lua:581
--Port(Syslog):2020-04-29T01:31:56 refreshing overlay2 maps_scene.lua:133
--Port(Syslog):2020-04-29T01:31:56 refreshOverlay2:2.488281 0.441406 0.000000 becomes 20384.000000 3616.000000 5.000000 via 0.000122 maps_scene.lua:141
--Port(Syslog):2020-04-29T01:31:56 refreshOverlay2:2.488281 0.441406 0.000000 becomes 79.625000 14.125000 5.000000 maps_scene.lua:154

--Port(Syslog):2020-04-29T01:32:59 Table[MapTap] = __index=table: 0x7b1405fb00 callback=function: 0x7b0d3560c0 idx=0 isTap=true moveX=0 moveY=0 oldX=583 oldY=525 screenX=583 screenY=525 stoped=false tapCount=1 tapTime=0.068 target=0x7b0c019838 <MOAIGraphicsProp> touchingProp=0x7b0c019838 <MOAIGraphicsProp> type=touchUp
-- x=583 y=525 maps_scene.lua:573
--Port(Syslog):2020-04-29T01:32:59 worldOverlay @ 0,0 group1 @ 0,-130 mapGroup @ 156,580 TAP @ 427,75 maps_scene.lua:581
--Port(Syslog):2020-04-29T01:32:59 refreshing overlay2 maps_scene.lua:133
--Port(Syslog):2020-04-29T01:32:59 refreshOverlay2:1.667969 0.292969 0.000000 becomes 13664.000000 2400.000000 5.000000 via 0.000122 maps_scene.lua:141
--Port(Syslog):2020-04-29T01:32:59 refreshOverlay2:1.667969 0.292969 0.000000 becomes 53.375000 9.375000 5.000000 maps_scene.lua:154

--[MOAI-1] 01:35:05 Table[MapTap] = __index=table: 033C4388 callback=function: 0FBB7330 idx=111 isTap=true moveX=0 moveY=0 oldX=250 oldY=256 screenX=250 screenY=256 stoped=false tapCount=1 tapTime=0.124 target=0F695660 <MOAIGraphicsProp> touchingProp=0F695660 <MOAIGraphicsProp> type=touchUp
-- x=250 y=256 @maps_scene.lua:573
--[MOAI-1] 01:35:05 worldOverlay @ 0,0 group1 @ -130,0 mapGroup @ 424,127 TAP @ -44,128 @maps_scene.lua:581
--[MOAI-1] 01:35:05 refreshing overlay2 @maps_scene.lua:133
--[MOAI-1] 01:35:05 refreshOverlay2:-0.171875 0.502930 0.000000 becomes -352.000000 1030.000000 3.000000 via 0.000488 @maps_scene.lua:141
--[MOAI-1] 01:35:05 refreshOverlay2:-0.171875 0.502930 0.000000 becomes -1.375000 4.023438 3.000000 @maps_scene.lua:154

print(string.format("world @ %d,%d group1 @ %d,%d mapGroup @ %d,%d TAP @ %d,%d", wx, wy, gx, gy, mx, my, tx, ty))
											mapBackground2.xt, mapBackground2.yt, mapBackground2.zt = tx/256, ty/256, 0
											refreshOverlay2()
											--worldOverlay:setTexture(tilemgr:getContentImage(osmTiles:getZoom()))
										end
									end)
	group1:addChild(worldOverlay)

	local target = Sprite { name="target", texture = "icons/baseline_center_focus_weak_black_48.png" }
	target:setSize(32,32)
	target:setPos((-target:getWidth())/2, (-target:getHeight())/2)
	target:setAlpha(0.15)
	group1:addChild(target)

	groupLabel2 = TextBackground { text="This is the label", layer=layer, textSize=14 } --*config.Screen.scale
	groupLabel2:setColor(unpack(textColor))
	groupLabel2:fitSize()
	groupLabel2:setAlignment ( MOAITextBox.CENTER_JUSTIFY, MOAITextBox.CENTER_JUSTIFY )
	--groupLabel:setLoc(groupLabel:getWidth()/2+config.Screen.scale, height-groupLabel:getHeight()/2)
	groupLabel2:setLoc(128,groupLabel2:getHeight()/2)
	groupLabel2:setPriority(2000000000)
	group2:addChild(groupLabel2)

	local z = osmTiles:getZoom()
	local clat, clon = osmTiles:getCenter()
	local xd, yd = latlonToXY(clat,clon,z)
	local zd = z<8 and z or 8
	--local xt, yt, zt = math.floor(xd/2^zd), math.floor(yd/2^zd), z-zd
	local xt, yt, zt = xd/2^zd, yd/2^zd, z-zd
	local image, stretch = tilemgr:getTileImageOrStretch(math.floor(xt),math.floor(yt),zt, function (new) newBackground2(new, xt, yt, zt) end)
	setBackground2(image, xt, yt, zt)
	group2:addChild(mapBackground2)
    worldOverlay2 = Sprite {texture = tilemgr:getContentImage2(xd,yd,z, groupLabel2), layer = layer, left = 130, top = (height-256)/2}
	worldOverlay2:setPos(0,0)
	worldOverlay2:setAlpha(0.5)
	worldOverlay2:addEventListener("touchUp", function(e)
										print(printableTable("MapTap2",e))
										if e.isTap then
--[[
local clat, clon = osmTiles:getCenter()
local count, vmin, vmax = tilemgr:spiralPreloadTiles(clat,clon,config.Range,osmTiles:getZoom(),function(x,y,z,status) print(string.format("Spiral %s %d/%d/%d", status and "loaded" or "FAILED", z, x, y)) end)
if count then
	toast.new(string.format("Loading %d Tiles",count), 5000)
else toast.new(vmin, 5000)
end
]]
											refreshOverlay2()
											--worldOverlay:setTexture(tilemgr:getContentImage(osmTiles:getZoom()))
										end
									end)
	group2:addChild(worldOverlay2)

	naviGroup = Group { layer=layer }
	naviGroup:setLayer(layer)
	group2:addChild(naviGroup)
	
	local center = Sprite { name="center", texture = "icons/baseline_center_focus_weak_black_48.png" }
	center:setSize(32,32)
	center:setPos((-center:getWidth())/2, (-center:getHeight())/2)
	center:setAlpha(0.25)
	center:addEventListener("touchUp", function(e)
										print(printableTable("centerTap",e))
										if e.isTap then
											stations:updateCenterStation()
											local z = osmTiles:getZoom()
											local clat, clon = osmTiles:getCenter()
											local xd, yd = latlonToXY(clat,clon,z)
											local zd = z<8 and z or 8
											--local xt, yt, zt = math.floor(xd/2^zd), math.floor(yd/2^zd), z-zd
											local xt, yt, zt = xd/2^zd, yd/2^zd, z-zd
											mapBackground2.xt, mapBackground2.yt, mapBackground2.zt = xt, yt, zt
											refreshOverlay2()
										end
									end)
	naviGroup:addChild(center)


	local function deltaMapTile(dx, dy)
		local xt, yt, zt = mapBackground2.xt+dx, mapBackground2.yt+dy, mapBackground2.zt
		local function slam(c,z)
			local z2 = 2^z
			if c < 0 then
				c = c + z2
			elseif c >= z2 then
				c = c - z2
			end
			return c
		end
		xt = slam(xt,zt) yt = slam(yt,zt)
		if mapBackground2.xt ~= xt or mapBackground2.yt ~= yt or mapBackground2.zt ~= zt then
print(string.format("map2 tile moving to %f %f zoom %f", xt, yt, zt))
			local image, stretch = tilemgr:getTileImageOrStretch(math.floor(xt),math.floor(yt),zt, function (new) newBackground2(new, xt, yt, zt) end)
			setBackground2(image, xt, yt, zt)
			local z = osmTiles:getZoom()
			local pow2 = 2^(z-zt)
			groupLabel2:setText("Refreshing...")
			worldOverlay2:setTexture(tilemgr:getContentImage2(xt*pow2,yt*pow2,z, groupLabel2))
		end
	end

	local left = Sprite { name="left", texture = "icons/baseline_keyboard_arrow_left_black_48.png" }
	left:setSize(32,32)
	left:setPos((-left:getWidth())/2-left:getWidth(), (-center:getHeight())/2)
	left:setAlpha(0.25)
	left:addEventListener("touchUp", function(e)
										print(printableTable("leftTap",e))
										if e.isTap then
											deltaMapTile(-1,0)
											--refreshOverlay2()
										end
									end)
	naviGroup:addChild(left)
	
	local right = Sprite { name="right", texture = "icons/baseline_keyboard_arrow_right_black_48.png" }
	right:setSize(32,32)
	right:setPos((-right:getWidth())/2+right:getWidth(), (-right:getHeight())/2)
	right:setAlpha(0.25)
	right:addEventListener("touchUp", function(e)
										print(printableTable("rightTap",e))
										if e.isTap then
											deltaMapTile(1,0)
											--refreshOverlay2()
										end
									end)
	naviGroup:addChild(right)

	local up = Sprite { name="up", texture = "icons/baseline_keyboard_arrow_up_black_48.png" }
	up:setSize(32,32)
	up:setPos((-up:getWidth())/2, (-up:getHeight())/2-up:getHeight())
	up:setAlpha(0.25)
	up:addEventListener("touchUp", function(e)
										print(printableTable("upTap",e))
										if e.isTap then
											deltaMapTile(0,-1)
											--refreshOverlay2()
										end
									end)
	naviGroup:addChild(up)

	local down = Sprite { name="down", texture = "icons/baseline_keyboard_arrow_down_black_48.png" }
	down:setSize(32,32)
	down:setPos((-down:getWidth())/2, (-down:getHeight())/2+down:getHeight())
	down:setAlpha(0.25)
	down:addEventListener("touchUp", function(e)
										print(printableTable("downTap",e))
										if e.isTap then
											deltaMapTile(0,1)
											--refreshOverlay2()
										end
									end)
	naviGroup:addChild(down)
	naviGroup:setPos(128,128)
	
	local test = naviGroup:getChildByName("left")
	print(string.format("Left=%s or %s", tostring(left), tostring(test)))

	--center = stations:getCenterStation()
	--symbol = getSymbolImage(center.symbol, center.stationID)
	--local x20, y20 = latlonToMap0(center.lat, center.lon)
	--print(string.format("%s is at %.3f %.3f or x20=%.3f y20=%.3f", center.stationID, center.lat, center.lon, x20, y20))
	--symbol:setLoc(x20, y20)
	--mapGroup:addChild(symbol)
	dot = getSymbolImage('\\/', '0@0')	-- // is red dot \\/ is black dot (with escape for \)
	local x20, y20 = latlonToMap0(osmTiles:getCenter())
	dot:setAlpha(0.25)
	dot:setLoc(128,128)
	dotvisible = true
	group1:addChild(dot)

	dot2 = getSymbolImage('\\/', '0@0')	-- // is red dot \\/ is black dot (with escape for \)
	local x20, y20 = latlonToMap0(osmTiles:getCenter())
	dot2:setAlpha(0.25)
	dot2:setLoc(128,128)
	dot2visible = true
	group2:addChild(dot2)

--[[
    worldOverlay = Sprite {texture = tilemgr:getContentImage(osmTiles:getZoom()), layer = layer, left = 0, top = (height-256)/2}
	worldOverlay:addEventListener("touchUp", function(e)
										print(printableTable("MapTap",e))
										if e.isTap then
											worldOverlay:setTexture(tilemgr:getContentImage(osmTiles:getZoom()))
										end
									end)
]]

	moveAndScaleMapGroup(width, height)

end
