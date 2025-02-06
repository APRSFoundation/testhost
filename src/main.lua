debugLines = false

--print("mina:lua version:"..tostring(_VERSION))
--for k,v in pairs( _G ) do print(tostring(k).." "..tostring(v)) end

MOAILogMgr.log ( 'main:Before myinit\n' )
require "myinit"
MOAILogMgr.log ( 'main:After myinit\n' )

MOAISim.setGCStep(200)	-- Arbitrarily high(ish) value...

function string:split( inSplitPattern, outResults )
 
   if not outResults then
      outResults = {}
   end
   local theStart = 1
   local theSplitStart, theSplitEnd = string.find( self, inSplitPattern, theStart )
   while theSplitStart do
      table.insert( outResults, string.sub( self, theStart, theSplitStart-1 ) )
      theStart = theSplitEnd + 1
      theSplitStart, theSplitEnd = string.find( self, inSplitPattern, theStart )
   end
   table.insert( outResults, string.sub( self, theStart ) )
   return outResults
end

local showIDs = { }
showIDs["ME"]=true
showIDs["crumbShort"]=true
showIDs["crumbsLong"]=true
showIDs["ME-trkseg"]=true
showIDs["ME-Tracks"]=true
showIDs["ISS"]=true
showIDs["KJ4ERJ-1"]=true
showIDs["KJ4ERJ-7"]=true
showIDs["KJ4ERJ-12"]=true
showIDs["KJ4ERJ-SM"]=true
showIDs["G6UIM"]=true 
showIDs["FETCH-ER"]=true 

function pairsByKeys (t, f)
  local a = {}
  for n in pairs(t) do table.insert(a, n) end
  table.sort(a, f)
  local i = 0      -- iterator variable
  local iter = function ()   -- iterator function
	i = i + 1
	if a[i] == nil then return nil
	else return a[i], t[a[i]]
	end
  end
  return iter
end

function shouldIShowIt(ID)
	if Application:isMobile() then return true end
	return showIDs[ID]
end

if not MOAIEnvironment.appDisplayName or type(MOAIEnvironment.appDisplayName) ~= 'string' or #MOAIEnvironment.appDisplayName < 1 then
	print('main:MOAIEnvironment.appDisplayName is '..type(MOAIEnvironment.appDisplayName)..'('..tostring(MOAIEnvironment.appDisplayName)..')')
	MOAIEnvironment.appDisplayName = 'APRSISMO'
	print('main:Defining MOAIEnvironment.appDisplayName to '..tostring(MOAIEnvironment.appDisplayName))
end

if not MOAIEnvironment.appVersion then
	print('main:Determining appVersion, lfs.dir = '..tostring(lfs.dir))
	local recent = 0
	for file in lfs.dir(".") do
		print('main:Checking '..file)
		if file:match("^.+%.lua$") then
			local modified = lfs.attributes(file,"modification")
			--print(file..' modified '..os.date("%Y-%m-%d %H:%M", modified))
			if modified > recent then recent = modified end
		else print('main:Nomatch')
		end
	end
	print('main:end lfs.dir loop')
	if recent > 0 then
		MOAIEnvironment.appVersion = os.date("!%Y-%m-%d %H:%M", recent)
	else MOAIEnvironment.appVersion = '*Simulator*'
	end
end

print('main:require toast')
local toast = require("toast");
print('main:require APRS')
local APRS = require("APRS")
print('main:require colors')
local colors = require("colors");
print('main:require latlon')
local LatLon = require("latlon")
print('main:require otp')
local otp = require("otp")
local BTPort	-- required below after config initializes
--local APRSIS	-- required below as it auto-starts -- No longer local but GLOBAL!
local osmTiles	-- required at the end
local service	-- required lower down...

print('main:require hp-modules')
local hp_modules = require "hp-modules"
print('main:require hp-config')
local hp_config = require "hp-config"

if Application:isDesktop() then
	if type(MOAIGfxDevice.enableTextureLogging) == 'function' then
		print("Remember to enableTextureLogging!")
		--MOAIGfxDevice.enableTextureLogging(true)
	end
	if type(MOAISim.setHistogramEnabled) == 'function' then
		MOAISim.setHistogramEnabled ( true )
	end
--	MOAIEnvironment.BTDevices = "GBS301(00:1B:DC:50:0C:5F)\r\n"..
--								"TH-D74(B0:B4:48:51:E2:0C)\r\n"..
--								"BTGPS(12:34:56:78:9A:B3)\r\n"..
--								"Uconnect 1C3CCCAB6GN148340(00:54:AF:61:C5:81)\r\n"
end

--local QSOs = require('QSOs')
--local QSO = require('QSO')

--local flower = require("flower")

print('main:require socket')
local socket = require("socket")	-- for socket.gettime()

local threads = {}
function accumulateThreadRun(name, elapsed)
 if not threads[name] then
	threads[name] = {}
	threads[name].first = os.time()
	threads[name].elapsed = 0
	threads[name].runs = 0
	threads[name].lastRuns = 0
 end
 threads[name].elapsed = threads[name].elapsed + elapsed
 threads[name].runs = threads[name].runs + 1
end 


function performWithDelay2 (name, delay, func, repeats, ...)
 local arg={...}
 if type(idleTimers) == 'nil' then idleTimers = 0 end
 idleTimers = idleTimers + 1
 
 --[[ if not simStarting then
	if type(simWasRunning) == 'nil' then simWasRunning = true end	-- Don't track during startup!
	if not simRunning then
		idleTimers = idleTimers + 1
	elseif not simWasRunning then
		simWasRunning = simRunning
		toast.new('sim now running, '..tostring(idleTimers)..' Timers Queued')
	end
	simWasRunning = simRunning
 end
]]

 local t = MOAITimer.new()
 local tStart = socket.gettime()
 if not func then func(unpack(arg)) end	-- Should not happen, but need to track it down!
 t:setSpan( delay/1000 )
 t:setListener( MOAITimer.EVENT_TIMER_END_SPAN,
   function ()
     t:stop()
     t = nil
	 --print("performWithDelay2:"..tostring(name)..":Invoking "..tostring(func).." with "..tostring(arg).." after "..tostring(socket.gettime()-tStart).."/"..tostring(delay/1000))
	 local start = MOAISim.getDeviceTime()
     local result = func( unpack( arg ) )
	 local elapsed = (MOAISim.getDeviceTime()-start)*1000
	 if elapsed > MOAISim.getStep()*1000 then
		print(string.format('performWithDelay2:%s took %.2fmsec vs step(%.2f)', name, elapsed, MOAISim.getStep()*1000))
	 end
	 accumulateThreadRun(name, elapsed)
	 if name == 'debug' then print('DebugPerform:result='..tostring(result)..' repeats='..tostring(repeats)) end
		if result ~= 'cancel' and repeats then
			if repeats > 0 then
				local remaining = repeats - 1
				if remaining == 1 then remaining = nil end
				performWithDelay2( name, delay, func, remaining, unpack( arg ) )
			elseif repeats == 0 then
			   performWithDelay2( name, delay, func, 0, unpack( arg ) )
			end
		end
   end
 )
 t:start()
 return t
 end
 
function performWithDelay (delay, func, repeats, ...)
	local arg={...}
	local info = debug.getinfo( 2, "Sl" )
	local where = info.source..':'..info.currentline
	if where:sub(1,1) == '@' then where = where:sub(2) end
	return performWithDelay2 (where, delay, func, repeats, unpack(arg))
--[[
 local t = MOAITimer.new()
 if not func then func(unpack(arg)) end	-- Should not happen, but need to track it down!
 t:setSpan( delay/1000 )
 t:setListener( MOAITimer.EVENT_TIMER_END_SPAN,
   function ()
     t:stop()
     t = nil
     local result = func( unpack( arg ) )
		if result ~= 'cancel' and repeats then
			if repeats > 1 then
				performWithDelay( delay, func, repeats - 1, unpack( arg ) )
			elseif repeats == 0 then
			   performWithDelay( delay, func, 0, unpack( arg ) )
			end
		end
   end
 )
 t:start()
 return t
]]
end

function printableTable(w, t, s, p)
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
				table.insert(a, n)
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

print(printableTable("arg",arg))

--[[local G_Count
local OldGs = {}
_ = true	-- make it a global first!
local function monitorGlobals(where)
	local now = MOAISim.getDeviceTime()*1000
	where = where or ""
	if #where then where = where..': ' end
	local nowCount = 0
	local newOnes = 0
	for k,v in pairs( _G ) do
		nowCount = nowCount + 1
		if G_Count and not OldGs[k] then
			print("*** New global("..tostring(k)..'):'..tostring(v))
			if type(v) == 'table' then print(printableTable(tostring(k),v)) end
			newOnes = newOnes + 1
		end
		OldGs[k] = now
	end
	for k,v in pairs( OldGs ) do
		if OldGs[k] ~= now then
			print("*** Removed global("..tostring(k)..')')
			OldGs[k] = nil
		end
	end
	if G_Count ~= nowCount then
		if G_Count then
			print(where..tostring(nowCount)..' Globals now defined ('..tostring(newOnes)..' new)')
		else print(where..tostring(nowCount)..' Globals initially defined')
		end
		G_Count = nowCount
	end
	return (newOnes > 0)
end
monitorGlobals('Initial')
performWithDelay(1000,function() monitorGlobals('timer') end,0)
]]

local stations = require('stationList')

local notificationIDs = {}

cancelNotification = function(id)
	toast.destroy(id)
end

scheduleNotification = function(when, options)
	if type(options) == 'table' and type(options.alert) == 'string' then
		print('scheduleNotification('..tostring(options.alert)..')')
		local onTap = nil
		print(printableTable('scheduleNotification:options',options))
		if type(options.custom) == 'table' then print(printableTable('scheduleNotification:custom',options.custom)) end
		if type(options.custom) == 'table' and options.custom.name == 'message' and options.custom.QSO then
--custom = { name="message", msg=msg, QSO=QSO } }
			print('scheduleNotification:setting onTap')
			onTap = function()
					print('scheduleNotification:onTap:opening QSO:'..options.custom.QSO.id)
					SceneManager:openScene("QSO_scene", { animation="popIn", QSO = options.custom.QSO })
				end
		end
		return toast.new(options.alert, nil, onTap)--,5000)
	end
	return nil
end

--local myConfig = require("myconfig")
if Application:isDesktop() then
	config = require("myconfig").new(MOAIEnvironment.appDisplayName..".xml", "." )
else
	config = require("myconfig").new(MOAIEnvironment.appDisplayName..".xml", MOAIEnvironment.documentDirectory or "." )
end
if type(config.Syslog) == "nil" then config.Syslog = {} end

local function validateStationID(value)
	print('validateStationID:'..tostring(value))
	value = string.upper(trim(value))
	if #value <= 0 then return nil end
	return value
end

local function updateISEnabled()
	if APRSIS then
		if config.APRSIS.Enabled then
			APRSIS:start()
		else APRSIS:stop()
		end
else print('updateISServer:APRSIS Not Yet Initialized!')
	end
end

local function updateISServer()
	if APRSIS then
print('updateISServer:disconnecting APRS-IS...')
		APRSIS:setServerPort(config.APRSIS.Server, config.APRSIS.Port)
		APRSIS:setStationID(config.StationID, config.PassCode)
		APRSIS:triggerReconnect("Configuration Change restart")
else print('updateISServer:APRSIS Not Yet Initialized!')
	end
end

local function updateFilter()
	if service then
		if APRSIS then
			APRSIS:setRange(config.Range)
			APRSIS:setFilter(config.Filter)
		end
		--service:triggerFilter()
else print('updateFilter:service Not Yet Initialized!')
	end
end

local function updateStationID()
	print('updateStationID to '..tostring(config.StationID))
	local newValue = validateStationID(config.StationID)
	if newValue then
		config.StationID = newValue
		myStation.stationID = config.StationID
		updateISServer()
	end
end

--
local client, clientServer
--local GPSSwitch
local gpsSwitch -- Actually a segmented control...
local sleepSwitch
local initialized = false

local function updateMySymbol()
	myStation.symbol = config.Beacon.Symbol
	stations:setupME()
end

local function updateOTPSecret()
	otp:setSecret(config.OTP.Secret)
	print('updateOTPSecret:Next secret is '..otp:getPassword(config.OTP.Sequence))
	config.OTP.Secret = ''
end

local function updateOTPSequence()
	config.OTP.Sequence = tonumber(config.OTP.Sequence)
	otp:setSequence(config.OTP.Sequence)
	print('updateSecret:Next secret is '..otp:getPassword(config.OTP.Sequence))
end

local locationListening

local GPSd
if Application:isDesktop() then
	GPSd = require('GPSd')
print('GPSd loaded as '..tostring(GPSd))
else print('NOT loading GPSd on non-desktop()')
end

local maxAcceleration = 0
local gpsDisabled = false

StillTime = tostring(MOAIEnvironment.GPSListening).."\n hh:mm:ss "
local function monitorAccelerometer(enabled)
if MOAIInputMgr.device.level then
	if enabled then
		local mabs = math.abs
		local mmax = math.max
		local lx, ly, lz = MOAIInputMgr.device.level:getLevel()
		local tLast = os.time()
		local tMove = os.time()
		local mAccel = 0
		local function onLevelEvent ( x, y, z )
			local tThis = os.time()
			local mx, my, mz = lx-x, ly-y, lz-z
			lx, ly, lz = x, y, z

local threshold = 0.5
local dAccel = mmax(mabs(mx),mabs(my),mabs(mz))
			if dAccel > maxAcceleration then maxAcceleration = dAccel end
			if dAccel > threshold then
				mAccel = dAccel
--				if tMove ~= tThis then
--					print (string.format("delta:x=%.2f y=%.2f z=%.2f was %s", mx, my, mz, StillTime))
--				end
				tMove = tThis
				if gpsDisabled and config.Enables.GPS and MOAIAppAndroid and type(MOAIAppAndroid.setGPSEnabled) == 'function' then
					gpsDisabled = false;
					print("setGPSEnabled(true)="..tostring(MOAIAppAndroid.setGPSEnabled(true)))
	--			else print("NOT Enabling Android GPS!")
				end
			end

			local dTime = tThis-tMove
			local newTime = string.format("%s %.2f\n%2d:%02d:%02d.",
											tostring(MOAIEnvironment.GPSListening),
											mAccel,
											math.floor(dTime/(60*60)),
											math.floor((dTime/60)%60),
											math.floor(dTime%60))
			if newTime ~= StillTime and stilltext then
				local x,y = stilltext:getLoc()
				stilltext:setString ( newTime );
				stilltext:fitSize()
				stilltext:setLoc(x,y)
				StillTime = newTime
	--			print("Still:"..StillTime)
			end

			if dTime > 2*60 then	-- 2 minutes to turn off GPS
				if not gpsDisabled and config.Enables.GPS and MOAIAppAndroid and type(MOAIAppAndroid.setGPSEnabled) == 'function' then
					gpsDisabled = true
					print("setGPSEnabled(false)="..tostring(MOAIAppAndroid.setGPSEnabled(false)))
					if gpstext then
						performWithDelay(1000, function ()
							local text = string.format('%s %s%s',
										tostring(MOAIEnvironment.GPSListening),
										"Still ",
										FormatLatLon(myStation.lat, myStation.lon, 1, 0))
							gpsUpdate = text
						end)
					end
--				else print("NOT Disabling Android GPS!")
				end
			end
		end
		print("invoking MOAIInputMgr.device.level:setCallback")
		MOAIInputMgr.device.level:setCallback ( onLevelEvent )
	else
		if stilltext then
			local x,y = stilltext:getLoc()
			StillTime = "off"
			stilltext:setString ( StillTime );
			stilltext:fitSize()
			stilltext:setLoc(x,y)
		end
		print("invoking MOAIInputMgr.device.level:setCallback")
		MOAIInputMgr.device.level:setCallback ( nil )
	end
else print("MOAIInputMgr.device.level NOT Defined")
end 
end


function updateGPSEnabled()
	print("updateGPSEnabled("..tostring(config.Enables.GPS)..")")
	--GPSSwitch:setState( { isOn=config.Enables.GPS, isAnimated=false } )
	if config.Enables.GPS then
		if gpstext then gpstext:setColor(0, 0, 0, 1.0) end
		if gpstext then gpstext:setString ( "GPS On" ) end
		if not locationListening then
			locationListening = true
			-- Turn it ON here
			if GPSd and (config.gpsd.Server ~= '') and tonumber(config.gpsd.Port) then GPSd:start(config) else print('not starting GPSd') end
			if service then
				if MOAIInputMgr.device.location then
					MOAIInputMgr.device.location:setCallback(service.locationListener)
					if MOAIAppAndroid and type(MOAIAppAndroid.setGPSEnabled) == 'function' then
						print("setGPSEnabled="..tostring(MOAIAppAndroid.setGPSEnabled(true)))
					else print("NOT Enabling Android GPS!")
					end
					monitorAccelerometer(true)
				else
					if gpstext then gpstext:setColor(192/255, 192/255, 0/255, 1) end	-- Yellow(ish) for disabled
					if gpstext then gpstext:setString ( "No GPS" ) end
				end
				service:triggerPosit('GPS:on',5000)
			else print('updateGPSEnabled:service Not Yet Initialized!')
			end
		end
	else
		if gpstext then gpstext:setColor(192/255, 192/255, 0, 1) end	-- Yellow(ish) for disabled
		if gpstext then gpstext:setString ( "GPS Off" ) end
		if speedtext then speedtext:setString("") end
		if myStation then myStation.course, myStation.speed = nil, nil end	-- No GPS == NOT Moving!
		if locationListening then
			locationListening = false
			-- Turn it OFF here
			if GPSd then GPSd:close() else print('not stopping GPSd') end
			if service then
				if MOAIInputMgr.device.location then
					MOAIInputMgr.device.location:setCallback(nil)
					if MOAIAppAndroid and type(MOAIAppAndroid.setGPSEnabled) == 'function' then
						print("setGPSEnabled="..tostring(MOAIAppAndroid.setGPSEnabled(false)))
					else print("NOT Disabling Android GPS!")
					end
					monitorAccelerometer(false)
					if gpstext then gpstext:setString ( "GPS Off" ) end
					performWithDelay(1000,function() gpstext:setString("GPS Off or "..tostring(MOAIEnvironment.GPSListening)) end)
				else
					if gpstext then gpstext:setColor(192/255, 192/255, 0/255, 1) end	-- Yellow(ish) for disabled
					if gpstext then gpstext:setString ( "No GPS" ) end
				end
				service:triggerPosit('GPS:off',0)
			else print('updateGPSEnabled:service Not Yet Initialized!')
			end
		end
	end
end

local function updateGPSdServer()
	if GPSd then
		GPSd:stop()	-- It'll reconnect within 60 seconds if it was ever started
		GPSd:start(config)	-- Restart it
	end
end

function updateKeepAwake()
	if MOAIAppAndroid and type(MOAIAppAndroid.setKeepScreenOn) == 'function' then
		print("setKeepScreenOn="..tostring(MOAIAppAndroid.setKeepScreenOn(config.Enables.KeepAwake)))
	else print("NOT setting Android KeepScreenOn!")
	end
	if initialized and not config.Warning.KeepAwake then
		--native.showAlert( "Keep Awake?", "Staying awake may adversely impact battery life.  Just thought you might like to know.", {"OK"} )
		config.Warning.KeepAwake = true
	end
	-- system.setIdleTimer(not config.Enables.KeepAwake)
end

function updateBluetooth()

	if config.Bluetooth then
		if MOAIAppAndroid and type(MOAIAppAndroid.setBluetoothDevice) == 'function' then
			print("setBluetoothDevice="..tostring(MOAIAppAndroid.setBluetoothDevice(config.Bluetooth.Device)))
		else print("NOT setting Android BluetoothDevice!")
		end
		if MOAIAppAndroid and type(MOAIAppAndroid.setBluetoothEnabled) == 'function' then
			print("updateBluetooth:config.Bluetooth.Enabled="..tostring(config.Bluetooth.Enabled))
			if not config.Bluetooth.Enabled then	-- If disabling, execute the closeCmds
				if BTPort then
					BTPort:doCmds(closeCmds, function()
									print("setBluetoothEnabled("..tostring(config.Bluetooth.Enabled)..")="..tostring(MOAIAppAndroid.setBluetoothEnabled(config.Bluetooth.Enabled)))
									end)
				end
			else print("setBluetoothEnabled("..tostring(config.Bluetooth.Enabled)..")="..tostring(MOAIAppAndroid.setBluetoothEnabled(config.Bluetooth.Enabled)))
			end
		else print("NOT setting Android BluetoothEnabled!")
		end
	end
end

local function bluetoothChooser(config, id, newValue)
	if MOAIEnvironment.BTDevices then
		local entries = { }
		for device in string.gmatch(MOAIEnvironment.BTDevices,"[^\r\n]+") do
			local name, address = string.match(device,"(.-)%((.-)%)")
			if name and address then
				table.insert(entries, {label=name, value=name, detail=address})
			else toast.new("BT:Failed to parse "..tostring(device))
			end
		end
		SceneManager:openScene("chooser_scene", {config=config, titleText="Select BT Device", entries=entries, newValue=newValue, animation = "popIn", backAnimation = "popOut", })
	else
		SceneManager:openScene("chooser_scene", {config=config, titleText="No BT Devices", values={"** No Paired Devices **", "Please Pair A Device"}, newValue=function() end, animation = "popIn", backAnimation = "popOut", })
	end
end

function updateCommands()
	if BTPort and config and config.Bluetooth then
		BTPort:setCommands(config.Bluetooth.CmdFile)
	end
end

local function commandChooser(config, id, newValue)
	local function fileChosen(f)
		print(printableTable("fileChosen",f))
		newValue(MOAIFileSystem.getAbsoluteFilePath(f))
	end
	SceneManager:openScene("file_scene", {match="^Cmd-.+%.xml$", config=config, titleText="Select Command File", newValue=fileChosen, animation = "popIn", backAnimation = "popOut", })
end


local function dropboxChooser(config, id, newValue)
	print("Activated dropboxChooser")
--[[
config:addString("Dropbox", "Dropbox.AccessCode", "Code returned by Dropbox", -1, "")
config:addString("Dropbox", "Dropbox.AccessToken", "Token returned by Dropbox", -1, "")
]]

	if config.Dropbox.AccessToken ~= '' then
		local function dropboxChosen(f)
			print(printableTable("dropboxChosen",f))
			newValue(f)
		end
		SceneManager:openScene("dropbox_scene", {config=config, titleText="Select Dropbox File", newValue=dropboxChosen, animation = "popIn", backAnimation = "popOut", })
--[[
		local entries = { }

		local stream = MOAIMemStream.new ()
		stream:open ( )

		local content = nil

		local function getComplete( task, responseCode )
			local streamSize = stream:getLength()

			if responseCode ~= 200 then
				print ( "getComplete:Network error:"..responseCode)
			elseif streamSize == 4294967295 then
				print ( "getComplete:Size:"..streamSize)
			else
				stream:seek(0)
				content = stream:read()
			end
		end

		content = nil

		if true then
			local task = MOAIHttpTask.new ()
			task:setVerb ( MOAIHttpTask.HTTP_POST )
			task:setUrl ( "https://api.dropboxapi.com/2/files/list_folder" )
			task:setHeader ( "Authorization", "Bearer "..config.Dropbox.AccessToken )
			task:setHeader ( "Content-Type", "application/json" )
			local body = "{\"path\": \"\"}"
			print("Body="..body)
			task:setBody ( body )
			task:setStream ( stream )
			task:setTimeout ( 10 )
			task:setCallback ( getComplete )
			task:setUserAgent ( 'APRSISMO' )
			task:setVerbose ( true )
			local me = MOAICoroutine:currentThread()
			if me then
				task:performAsync()
				while task:isBusy() do
					coroutine.yield()
				end
			else
				task:performSync ()
			end
		end

		if content then
			local json = require("json")
			local success, values = pcall(json.decode, json, content)
			if not success then
				print('DropboxCode:json.decode('..values..') on:'..content)
			--local values = json:decode(content)
			elseif type(values) == 'table' then
				print(printableTable('list_folder:json', values, "\n"))
				if type(values.entries) == 'table' then
					for i, e in ipairs(values.entries) do
						print(printableTable('list_folder:entries['..tostring(i)..']', e, "\n"))
						if e[".tag"] == "folder" then
							table.insert(entries, {label=e.name, value=e.path_display, detail=e.path_display})
						elseif e[".tag"] == "file" then
							table.insert(entries, {label=e.name, value=e.path_display, detail=tostring(e.size).." Mod:"..tostring(e.server_modified)})
						else
							table.insert(entries, {label=e.name, value=e.path_display, detail=tostring(e[".tag"])})
						end
					end
				end
				-- has values.cursor and values.has_more for looping if necessary
			end
		end

		SceneManager:openScene("chooser_scene", {config=config, titleText="Select Dropbox file", entries=entries, newValue=newValue, animation = "popIn", backAnimation = "popOut", })
]]
	elseif config.Dropbox.AccessCode ~= '' then
--[[
curl https://api.dropbox.com/oauth2/token \
    -d code=<AUTHORIZATION_CODE> \
    -d grant_type=authorization_code \
    -d redirect_uri=<REDIRECT_URI> \
    -u <APP_KEY>:<APP_SECRET>
Got:
{"access_token": "DXkqwNYZX-gAAAAAAAAjvQJrTnJFncTJyCID6K_h4_BDkwqZitWXbgXXQ1UsuAw-", "token_type": "bearer", "uid": "74000021", "account_id": "dbid:AABYlPM5mdwQ-CVkOtI15EDtV7emHfNxgIE"}
]]
		SceneManager:openScene("chooser_scene", {config=config, titleText="No Dropbox", values={"** No Dropbox Token **", "Please approve APRSISMO access"}, newValue=function() end, animation = "popIn", backAnimation = "popOut", })
	else
	
if MOAIApp then
	if type(MOAIApp.openURL) == 'function' then
		MOAIApp.openURL("https://www.dropbox.com/oauth2/authorize?response_type=code&client_id=f2xxipuqrcaytsu&redirect_uri=http://localhost:6362/APRSISMO.code")
	else toast.new("Oops, Missing MOAIApp.openURL("..type(MOAIApp.openURL)..")!")
	end
else toast.new("Oops, Missing MOAIApp("..type(MOAIApp)..")!")
end
		SceneManager:openScene("chooser_scene", {config=config, titleText="No Dropbox", values={"** No Dropbox Code **", "Please approve APRSISMO access"}, newValue=function() end, animation = "popIn", backAnimation = "popOut", })
	end
end






local function symbolChooser(config, id, newValue)
	local function symbolChosen(s)
		newValue(s)
	end
	SceneManager:openScene("symbol_scene", {config=config, titleText="Select Symbol",
											default=config.Beacon.Symbol, forces = {"/$", "/l"},
											newValue=symbolChosen,
											animation = "popIn", backAnimation = "popOut", })
end

local telem = nil
function updateTelemetryEnabled()
print("telemetry:telem="..tostring(telem))
	if not telem then
		telem = require('telemetry')
print("telemetry:telem="..tostring(telem).." DEFINING!")
		telem:definePoint("Acceleration", "Raw", 0,0.01,0, function()
																local temp = maxAcceleration
																maxAcceleration = 0
																return temp
															end)
		telem:definePoint("Battery", "Percent", 0,1,0, function()
																if type(MOAIEnvironment.BatteryPercent) ~= 'nil' then
																	local Perc = tonumber(MOAIEnvironment.BatteryPercent)
																	if Perc then
																		return Perc
																	end
																end
																return 0
															end)
--		telem:definePoint("Charging/AC", "Chart/On/Off", 0,1,0, function() return 0 end)
--[[
		telem:definePoint("GPS+Sat", "Sats/On/Off", 0,1,0, function()
																local v = 2
																if config.Enables.GPS then
																	if MOAIEnvironment.GPSListening == 'true' then
																		v = 48
																		if tonumber(MOAIEnvironment.SatInUse) then
																			v = v + tonumber(MOAIEnvironment.SatInUse)*5
																			if v > 95 then v = 95 end
																		end
																	elseif MOAIEnvironment.GPSListening == 'false' then
																		v = 25
																	else
																		v = 12
																	end
																end
																return v
															end)
]]
		telem:definePoint("Temperature", "NotSure", 0,0.1,0, function()
																if type(MOAIEnvironment.BatteryTemperature) ~= 'nil' then
																	local Temp = tonumber(MOAIEnvironment.BatteryTemperature)
																	if Temp then
																		return Temp/10.0
																	end
																end
																return 0
															end)
		telem:definePoint("SatInView", "Sats", 0,1,-1, function()
															if gpsDisabled or not config.Enables.GPS then
																return 0
															end
															return (tonumber(MOAIEnvironment.SatCount) or 0)+1
														end)
		telem:definePoint("SatInUse", "Sats", 0,1,-1, function()
															if gpsDisabled or not config.Enables.GPS then
																return 0
															end
															return (tonumber(MOAIEnvironment.SatInUse) or 0)+1
														end)
--		telem:definePoint("Current", "mA", 0,1,-500, function() return 0 end)
--		telem:definePoint("Phone Signal", "Percent", 0,1,0, function() return 0 end)
		telem:defineBit("A/C", "On", 1, function()
											if type(MOAIEnvironment.BatteryPlugged) ~= 'nil' then
												if MOAIEnvironment.BatteryPlugged == 'AC' then
													return 1
												end
											end
											return 0
										end)
		telem:defineBit("Charging", "Yes", 1, function()
											if type(MOAIEnvironment.BatteryStatus) ~= 'nil' then
												if MOAIEnvironment.BatteryStatus == 'Charging' then
													return 1
												end
											end
											return 0
										end)
		telem:defineBit("GPS", "Enabled", 1, function() return config.Enables.GPS and 1 or 0 end)
		telem:defineBit("GPS", "On", 1, function() return gpsDisabled and 0 or 1 end)
		telem:init('APRSISMO Stats',120)
	else telem:enableTelemetry(config.Enables.Telemetry)
print("telemetry:telem="..tostring(telem).." Enabling!")
	end
end

config:addGroup("Basic", "Basic configuration settings", true)
config:addString("Basic", "StationID", "Your callsign-SSID (MYCALL)", 9, "APRSIS-DR", nil, validateStationID, updateStationID)
config:addNumber("Basic", "PassCode", "APRS-IS PassCode", -1, -1, 99999, updateISServer)
--config:addString("Basic", "Beacon.Symbol", "APRS Symbol Table + Identifier", 2, Application:isMobile() and "/$" or "/l", '^..$', velidateSymbol, updateMySymbol)
config:addChooserString("Basic", "Beacon.Symbol", "APRS Symbol Table + Identifier", 2, Application:isMobile() and "/$" or "/l", symbolChooser, updateMySymbol)
config:addString("Basic", "Beacon.Comment", "Beacon Comment text", 43, MOAIEnvironment.appDisplayName.." de KJ4ERJ")

config:addGroup("Enables", "A vast collection of feature enablers")
config:addBoolean("Enables", "Enables.GPS", "Enable Location awareness", true, updateGPSEnabled)
config:addBoolean("Enables", "Enables.AllowNetworkFix", "Allow network location (not recommended) ", false)
if MOAIAppAndroid and type(MOAIAppAndroid.setKeepScreenOn) == 'function' then
	config:addBoolean("Enables", "Enables.KeepAwake", "Keep device Awake while running", false, updateKeepAwake)
	config:addBoolean(nil, "Warning.KeepAwake", "Awake Warning Issued", false)
end
config:addBoolean("Enables", "Enables.SaveMyTrack", "Auto-Save (ME) Transmitted Posits", false)
config:addBoolean("Enables", "Enables.SaveMyCrumbs", "Auto-Save (ME) GPS BreadCrumbs", false)
config:addBoolean("Enables", "Enables.SaveCenterTrack", "Auto-Save Center Station Track", false)
--if MOAIEnvironment.SatCount then
	config:addBoolean("Enables", "Enables.Telemetry", "Enable automatic Telemetry", false, updateTelemetryEnabled)
--end

config:addGroup("APRSIS", "APRS-IS settings")
config:addBoolean("APRSIS", "APRSIS.Enabled", "Keep connection to APRS-IS ", true, updateISEnabled)
config:addNumber("APRSIS", "Range", "Default m/ Range", 50, 1, 999, updateFilter)
config:addString("APRSIS", "APRSIS.Server", "APRS-IS Server to use", 128, "rotate.aprs2.net", nil, nil, updateISServer)
config:addNumber("APRSIS", "APRSIS.Port", "Server port (typically 14580)", 14580, 1, 65535, updateISServer)
config:addNumber("APRSIS", "APRSIS.QuietTime", "Max Idle seconds before Disconnect", 60, 0, 5*60)
config:addBoolean("APRSIS", "APRSIS.Notify", "Connection Status Notifications", true)
config:addNumber("APRSIS", "PassCode", "APRS-IS PassCode", -1, -1, 99999, updateISServer)
config:addString("APRSIS", "Filter", "Additional APRS-IS Filter", 256, "u/APWA*/APWM*", nil, nil, updateFilter)

config:addGroup("Beacon", "APRS Beacon settings")
config:addBoolean("Beacon", "Beacon.Enabled", "Allowed to beacon to APRS", true)
config:addBoolean("Beacon", "Beacon.AfterTransmit", "Suppress beacons until Location acquired", false)
config:addBoolean("Beacon", "Beacon.AutoAmbiguity", "Location accuracy implies ambiguity", true)
config:addString("Beacon", "Beacon.Symbol", "APRS Symbol Table + Identifier", 2, Application:isMobile() and "/$" or "/l", '^..$', velidateSymbol, updateMySymbol)
config:addString("Beacon", "Beacon.Comment", "Beacon Comment text", 43, MOAIEnvironment.appDisplayName.." de KJ4ERJ")
config:addBoolean("Beacon", "Beacon.Altitude", "Include Altitude if known", true)
config:addBoolean("Beacon", "Beacon.Speed", "Include CSE/SPD (allows Dead Reckoning)", true)
config:addBoolean("Beacon", "Beacon.TimestampDD", "Include DDHHMMz Timestamp", false)
config:addBoolean("Beacon", "Beacon.TimestampHH", "Include HHMMSSh Timestamp (trumps DD)", true)
config:addBoolean("Beacon", "Beacon.Speed", "Include Course and Speed if known (allows Dead Reckoning)", true)
config:addBoolean("Beacon", "Beacon.Why", "Include Transmit Pressure (useful for debuggin)", true)

--if not myConfig.Radar then myConfig.Radar = {} end
if MOAIAppAndroid and type(MOAIAppAndroid.setBluetoothDevice) == 'function' then
if MOAIAppAndroid and type(MOAIAppAndroid.setBluetoothEnabled) == 'function' then
	config:addGroup("Bluetooth", "Bluetooth SPP Configuration")
	config:addBoolean("Bluetooth", "Bluetooth.Enabled", "Maintain Bluetooth SPP Connection", false, updateBluetooth)
	config:addBoolean("Bluetooth", "Bluetooth.AutoReconnect", "Automatically ReConnect in Background", false)
	config:addChooserString("Bluetooth", "Bluetooth.Device", "Bluetooth Device Name", 128, "", bluetoothChooser, updateBluetooth)
	config:addBoolean("Bluetooth", "Bluetooth.IGate", "Gate Received Packets to APRS-IS", true)
	config:addBoolean("Bluetooth", "Bluetooth.TransmitPosits", "Enable Posit Transmitting over Bluetooth", true)
	config:addBoolean("Bluetooth", "Bluetooth.TransmitMessages", "Enable Message Transmitting over Bluetooth", true)
	config:addString("Bluetooth", "Bluetooth.Path", "Transmit Packet Path", 128, "WIDE1-1,WIDE2-1")
	config:addChooserString("Bluetooth", "Bluetooth.CmdFile", "Bluetooth Command Configuration", 256, "", commandChooser, updateCommands)
end
end

config:addGroup("Genius", "GeniusBeaconing™ settings")
config:addBoolean("Genius", "Genius.TimeOnly", "Beacon at MaxTime rate only", false)
config:addNumber("Genius", "Genius.MinTime", "Minimum (Seconds) between beacons", 15, 10, 5*60)
config:addNumber("Genius", "Genius.MaxTime", "Maximum (Minutes) between beacons", 30, 1, 60)
config:addBoolean("Genius", "Genius.StartStop", "Include Start/Stop detection", true)
config:addNumber("Genius", "Genius.HeadingChange", "Degrees of turn to trigger (180=none)", 80, 5, 180)
config:addNumberF("Genius", "Genius.ForecastError", "Allowed DeadReckon error before trigger (miles)", 0.1, 0.1, 2)
config:addNumber("Genius", "Genius.MaxDistance", "Maximum distance between beacons (miles)", 1.0, 0.5, 20)

config:addGroup("Screen", "On-Screen Controls and Indicators")
config:addNumber("Screen", "Screen.DFOpacity", "DF Highlight Opacity %", 10, 0, 100, function () osmTiles:refreshMap() end)
config:addNumber("Screen", "Screen.NWSOpacity", "NWS Area Opacity %", 10, 0, 100, function () osmTiles:refreshMap() end)
config:addBoolean("Screen", "Screen.PositPop", "Pop-and-Shrink Beacon Indicator", true)
config:addBoolean("Screen", "Screen.RedDot", "GeniusBeaconing™ Debug Aid (aka MeatBall)", true)
config:addBoolean("Screen", "Screen.RangeCircle", "Zoom/Range Indicator", true)
config:addNumberF("Screen", "Screen.SymbolSizeAdjust", "Symbol Size Scale Adjustment", 0, -10, 10, function() osmTiles:moveTo() end)
config:addNumber("Screen", "Screen.ScaleButtons", "Scale Options (1111-9999)", 1234, 1111, 9999)

if not (MOAIEnvironment.screenDpi and MOAIEnvironment.screenDpi > 0) or Application:isDesktop() then
	config:addNumber("Screen", "Screen.DPI", "DPI (sqrt(x^2+y^2)/diagonal)", 129, "*Unknown*")
end

function updateMBTiles()
	if osmTiles then osmTiles:newMBTiles() end
end

local function MBTilesChooser(config, id, newValue)
	print("MBTiles:Activating Chooser For "..tostring(id))
	local function confirmSelection(f)
		print("MBTiles:confirmSelect:"..tostring(f))
		return true
	end
	local function fileChosen(f)
		print("MBTiles:fileChosen:"..tostring(f))
		newValue(MOAIFileSystem.getAbsoluteFilePath(f))
	end
--	local dir = config.Map.MBTiles
--	if not dir or dir == '' then dir = getMBTilesDirectory() end
	local dir = getMBTilesDirectory()
	SceneManager:openScene("file_scene", {dir=dir, match="^.+%.mbtiles$", config=config,
											titleText="Select MBTiles Database",
											newValue=fileChosen, confirm=confirmSelection,
											animation = "popIn", backAnimation = "popOut", })
end

local function MBTilesChooserNone(config, id, newValue)
	print("MBTiles:Activating Chooser For "..tostring(id))
	local function confirmSelection(f)
		print("MBTiles:confirmSelect("..id.."):"..tostring(f))
		return true
	end
	local function fileChosen(f)
		print("MBTiles:fileChosen("..id.."):"..tostring(f))
		if f == '' then
			newValue(f)
		else newValue(MOAIFileSystem.getAbsoluteFilePath(f))
		end
	end
--	local dir = config.Map.MBTiles
--	if not dir or dir == '' then dir = getMBTilesDirectory() end
	local dir = getMBTilesDirectory()
	SceneManager:openScene("file_scene", {dir=dir, match="^.+%.mbtiles$", config=config,
											titleText="Select MBTiles Database",
											newValue=fileChosen, confirm=confirmSelection,
											extra={label="*None*", value="", detail="No Overlay (Top) Tiles"},
											animation = "popIn", backAnimation = "popOut", })
end

config:addGroup("Map", "Map Tile Server Settings")
config:addChooserString("Map", "Map.MBTiles", "Base MBTiles Database", 256, "LynnsTiles.mbtiles", MBTilesChooser, updateMBTiles)
config:addChooserString("Map", "Map.TopTiles", "Top MBTiles Database (no URL)", 256, "LynnsTiles.mbtiles", MBTilesChooserNone, updateMBTiles)
	
config:addGroup("Directory", "Various Storage Directories")
config:addString("Directory", "Dir.Tiles", "Directory For Tile Caching", 128, "")
config:addString("Directory", "Dir.Tracks", "Directory For Track GPX Files", 128, "")
config:addString("Directory", "Dir.GPX", "Directory For Displayed GPX Files", 128, "")

if Application:isDesktop() then
	config:addGroup("gpsd", "gpsd Location Source")
	config:addString("gpsd", "gpsd.Server", "Server IP or Name", 128, "", nil, nil, updateGPSdServer)
	config:addNumber("gpsd", "gpsd.Port", "Server port (typically 2947)", 2947, 1, 65535, updateGPSdServer)
end

config:addGroup("Vibrate", "Vibrator usage controls")
config:addBoolean("Vibrate", "Vibrate.Enabled", "Enable vibrator use", true)
config:addBoolean("Vibrate", "Vibrate.onTapStation", "Vibrate when station is tapped", true)

config:addGroup("Debug", "Debug Settings (Informed Use Only)")
config:addNumber("Debug", "Debug.WakeUpCount", "Seconds To Send WakeUp Messages", 2, 1, 30)
config:addBoolean("Debug", "Debug.WakeUpToast", "Toast WakeUp Messages", false)
config:addBoolean("Debug", "Debug.WakeUp", "Send WakeUp Messages to APRS(KJ4ERJ-12)", false)
config:addBoolean("Debug", "Debug.UpdateCounts", "LogCat Update Counters/Timers", false)
config:addBoolean("Debug", "Debug.ServiceBusy", "Periodically show Busy %", false)
config:addBoolean("Debug", "Debug.IgnoreNetwork", "Send Toast when Ignoring Network", false)
config:addBoolean("Debug", "Debug.RunProxy", "Run Proxy (requires restart)", false)
config:addBoolean("Debug", "Debug.ShowConnections", "Show Connection Changes via Toast", false)
config:addBoolean("Debug", "Debug.Performance", "Trace and report internal Performance", false)
config:addBoolean("Debug", "Debug.PurgeCrumbs", "Debug (message) Crumb Purging", false)
config:addBoolean("Debug", "Debug.TileFailure", "Tile Fetch Failures", false)
config:addBoolean("Debug", "Debug.ShowIPFS", "Show IPFS Debugging", false)
config:addBoolean("Debug", "Debug.ShowAccel", "Show Accelerometer (Lower Left)", false)

config:addGroup("Syslog", "Syslog Settings (Informed Use Only)")
config:addBoolean("Syslog", "Syslog.Enabled", "Enable Syslog Transmissions", false)
config:addString("Syslog", "Syslog.Server", "Syslog Server (ldeffenb.dnsalias.net:6514)",
					128, "ldeffenb.dnsalias.net:6514")

print("Adding Dropbox group")
config:addGroup("Dropbox", "Dropbox Access Settings")
config:addString("Dropbox", "Dropbox.AccessCode", "Code returned by Dropbox", 256, "")
config:addString("Dropbox", "Dropbox.AccessToken", "Token returned by Dropbox", 256, "")
config:addChooserString("Dropbox", "Dropbox.SelectedPath", "Test Selected Path", 256, "", dropboxChooser, nil)
config:addChooserString("Dropbox", "Dropbox.TestFile", "Test File Chooser", 256, "", commandChooser, nil)


config:addGroup("Remote", "Remote Command Setup")
config:addString("Remote", "OTP.Target", "Target CALLSIGN-SSID", 9, "", nil, nil, function () config.OTP.Target = validateStationID(config.OTP.Target) end)
config:addString("Remote", "OTP.Secret", "Secret Key for One-Time-Passwords", 128, "", nil, nil, updateOTPSecret)
config:addNumber("Remote", "OTP.Sequence", "Current Index for One-Time-Passwords", 0, 0, 8192, updateOTPSequence)
config:addNumber(nil, "OTP.secret1", "secret1", 10)
config:addNumber(nil, "OTP.secret2", "secret2", 20)
config:addNumber(nil, "OTP.secret3", "secret3", 30)
config:addNumber(nil, "OTP.secret4", "secret4", 40)

config:addGroup("About", "Program Version Information")
config:addString("About", "About.Version", "Build Date/Time", -1, "*Unknown*")
config.About.Version = MOAIEnvironment.appVersion or ''
config:addString("About", "ToCall", "Application ToCall", -1, "APWA01")
if MOAIEnvironment.appVersion:sub(1,4) > "2014" then
	config.ToCall = "APWA01"
else config.ToCall = "APWA00"
end
if type(config.APRSIS) == 'nil' then
	config.APRSIS = {}
end

print("MOAIEnvironment.screenDpi:"..tostring(MOAIEnvironment.screenDpi))
if Application:isMobile() then print("Application:isMobile"); end
if Application:isDesktop() then print("Application:isDesktop"); end

if not (MOAIEnvironment.screenDpi and MOAIEnvironment.screenDpi > 0) or Application:isDesktop() then
	MOAIEnvironment.screenDpi = config.Screen.DPI	-- sqrt(px^2+py^2)/inches diagonal sqrt(1920*1920+1080*1080)/17" = 129
end

local dpi = MOAIEnvironment.screenDpi or 240
config.Screen.scale = dpi/240

print('dpi:'..dpi..' scale:'..config.Screen.scale)

local SyslogHeader = nil	-- HEADER = PRI VERSION SP TIMESTAMP SP HOSTNAME SP APP-NAME SP PROCID SP MSGID
local udp = socket.udp()
local udpConnected = false
syslogIP = nil
local SyslogServer
local lastBSSID
local syslogNode, syslogPort

function setSyslogIP(IP, myCall)	-- nil or false to disable
	if not myCall then
		if config and config.StationID and config.StationID ~= "" then
			myCall = config.StationID
		else myCall = "-"
		end
	end
	SyslogHeader = (IP and tostring(IP) or "-").." APRSISMO "..tostring(myCall).." "
	syslogIP = nil	-- Force a re-configuration on next print
	lastBSSID = nil
end

setPrintCallback(function(output, where)
	if udp and config and config.Syslog then
		if config.Syslog.Server ~= SyslogServer then
			SyslogServer = config.Syslog.Server
			if SyslogServer and SyslogServer ~= "" then
				syslogNode, syslogPort = SyslogServer:match("%s*(.-):(%d+)%s*")
				if syslogNode and syslogPort and tonumber(syslogPort) then
					syslogIP = socket.dns.toip(syslogNode)
					syslogPort = tonumber(syslogPort)
					if syslogNode then
						syslogIP = nil	-- Force a re-configuration when re-enabled
						lastBSSID = nil
					else config.Syslog.Enabled = false;
					end
				else config.Syslog.Enabled = false;
				end
			else config.Syslog.Enabled = false;
			end
		end
		
		if not config.Syslog.Enabled then
			syslogIP = nil	-- Force a re-configuration when re-enabled
			lastBSSID = nil
		else
			if not SyslogHeader and config and config.StationID and config.StationID ~= '' then
				SyslogHeader = "- APRSISMO "..(config.StationID or "-").." "
			end
			local text = "<167>1 "..os.date("!%Y-%m-%dT%H:%M:%S ")..SyslogHeader..where.." - "..output:gsub("[\r\n]"," ")
			local BSSID = MOAIEnvironment.BSSID
			if Application:isDesktop()	-- I'm the only one that runs on the desktop (for now)!
			or BSSID == "2c:b0:5d:ab:08:17" or BSSID == "08:86:3b:70:84:f6"	or BSSID == "08:86:3b:70:84:f8"	-- My APs!
			then
				if syslogIP ~= '192.168.10.61' then
					syslogIP = '192.168.10.61'
					udp:setpeername("*",0)	-- Unbind first
					udp:setpeername(syslogIP, 514)
					MOAILogMgr.log("syslog:"..tostring(syslogIP).." udp:"..tostring(udp)..':setpeername\n')
				end
			elseif BSSID ~= lastBSSID then
				lastBSSID = BSSID
				syslogIP = nil
			end
			if not syslogIP then
				syslogIP, text2 = socket.dns.toip(syslogNode)
				if syslogIP then
					MOAILogMgr.log("Syslog:"..tostring(homeIP)..'\n')
					udp:setpeername("*",0) -- Unbind first
					udp:setpeername(syslogIP, syslogPort) -- Address the configured (firewall) port
					MOAILogMgr.log("syslog:"..tostring(syslogIP).." udp:"..tostring(udp)..':setpeername\n')
				else MOAILogMgr.log("syslog("..syslogNode..") dns error "..tostring(text2)..'\n')
				end
			end
			if syslogIP then
				local status, text2 = udp:send(text)
				if not status then MOAILogMgr.log("syslog:"..text2.." udp:"..tostring(udp)..":send("..tostring(syslogIP)..")\n") end
			else MOAILogMgr.log("syslog:NOT Sending "..text.."\n")
			end
		end
	
	end
end)



if not config.OTP.secret1 or not config.OTP.secret2 or not config.OTP.secret3 or not config.OTP.secret4 then
	config.OTP.secret1 = 1
	config.OTP.secret2 = 2
	config.OTP.secret3 = 3
	config.OTP.secret4 = 4
end
if not config.OTP.Sequence then
	config.OTP.Sequence = 0
end
otp:init({config.OTP.secret1, config.OTP.secret2, config.OTP.secret3, config.OTP.secret4},
		config.OTP.sequence, function(secret, sequence)
								print('Saving secret:'..tostring(secret[1])..' '..tostring(secret[2])..' '..tostring(secret[3])..' '..tostring(secret[4])..' Sequence:'..tostring(sequence))
								config.OTP.secret1 = secret[1]
								config.OTP.secret2 = secret[2]
								config.OTP.secret3 = secret[3]
								config.OTP.secret4 = secret[4]
								config.OTP.Sequence = sequence
								config:save('OTPChanged')
							end)

if configChanged or true then config:save('InitialDefaults') end

if tonumber(config.lastLat) and tonumber(config.lastLon) then
	myStation.lat = tonumber(config.lastLat)
	myStation.lon = tonumber(config.lastLon)
	print(string.format('ME is at %.5f %.5f', myStation.lat, myStation.lon))
else print(string.format('lastLat=%s(%s) lastLon=%s(%s)', type(config.lastLat), tostring(config.lastLat), type(config.lastLon), tostring(config.lastLon)))
end
if type(config.Beacon.Symbol) == 'string' and #config.Beacon.Symbol == 2 then
	myStation.symbol = config.Beacon.Symbol
end

local function Vibrate(yes)
	if yes and config.Vibrate.Enabled then
		--system.vibrate()
	end
end

simStarting = true
-- start and open
Application:start(hp_config)
SceneManager:openScene(hp_config.mainScene)	-- splash!

local function showDebugLines()
	--MOAIDebugLines.showStyle(MOAIDebugLines.PARTITION_CELLS)
	--MOAIDebugLines.showStyle(MOAIDebugLines.PARTITION_PADDED_CELLS)

	--MOAIDebugLines.setStyle(MOAIDebugLines.PROP_MODEL_BOUNDS,1,1,0,1,.75)	-- Purple
	--MOAIDebugLines.showStyle(MOAIDebugLines.PROP_MODEL_BOUNDS)

	MOAIDebugLines.setStyle(MOAIDebugLines.PROP_WORLD_BOUNDS,1,1,1,0,.75)	-- Yellow?
	MOAIDebugLines.showStyle(MOAIDebugLines.PROP_WORLD_BOUNDS, debugLines)

	MOAIDebugLines.setStyle(MOAIDebugLines.TEXT_BOX,1,1,0,0,.75)	-- Red
	MOAIDebugLines.setStyle(MOAIDebugLines.TEXT_BOX_BASELINES,1,0,1,0,.75)	-- Green
	if MOAIDebugLines.TEXT_BOX_LAYOUT then
		MOAIDebugLines.setStyle(MOAIDebugLines.TEXT_BOX_LAYOUT,1,0,0,1,.75)	-- Blue
	end

	MOAIDebugLines.showStyle(MOAIDebugLines.TEXT_BOX, debugLines)
	MOAIDebugLines.showStyle(MOAIDebugLines.TEXT_BOX_BASELINES, debugLines)
	if MOAIDebugLines.TEXT_BOX_LAYOUT then
		MOAIDebugLines.showStyle(MOAIDebugLines.TEXT_BOX_LAYOUT, debugLines)
	end
	
	if debugLines then
		local function makeRequiredDirectory(file, dir)
			if file == '' then return nil end
			local path = string.match(file, "(.+)/.+")
			local fullpath = dir..'/'..path
			MOAIFileSystem.affirmPath(fullpath)
			return fullpath
		end
		makeRequiredDirectory("logs/TestHost.log", "/sdcard/TestHost")
		local file = os.date("!/sdcard/TestHost/logs/%Y%m%d-%H%M%S.log")
		MOAILogMgr.openFile(file)
		print ( 'Logging Started\n' )
	else
		print ( 'Logging Stopped\n' )
		MOAILogMgr.closeFile()
	end
end

showDebugLines()	-- prime the pump

function toggleDebugLines()
	debugLines = not debugLines
	showDebugLines()
end

local function setConfigScreenSize()
local platformSize = ''
if type(Application.viewWidth)=='number' and type(Application.viewHeight)=='number' then
	platformSize=platformSize..' '..tostring(Application.viewWidth)..'x'..tostring(Application.viewHeight)
else print('viewWidth:'..type(Application.viewWidth)..' viewHeight:'..type(Application.viewHeight))
end
if type(MOAIEnvironment.screenDpi)=='number' then
	platformSize=platformSize..' at '..tostring(MOAIEnvironment.screenDpi)..' dpi'	-- trailing . for font sizing issues
else print('screenDPI:'..type(MOAIEnvironment.screenDpi))
end
config.Screen.Size = platformSize
print('platformSize:'..platformSize)
return platformSize
end
if #setConfigScreenSize() > 0 then
	config:addString("About", "Screen.Size", "Startup Screen Stats (static snapshot)", -1, "*Unknown*")
end
config:addString("About", "Screen.scale", "Calculated Scale (relative 240dpi)", -1, "*Unknown*")

--MOAISim.openWindow("MultiTrack", 64, 64)	-- Maybe? Nope, just one window :(

--[[
function onResize ( e )
	local width, height = e.width, e.height
	print('main:onResize:'..tostring(width)..'x'..tostring(height))
end
flower.Runtime:addEventListener(flower.Event.RESIZE, onResize)
]]

function onResize(width, height)
	local current = SceneManager:getCurrentScene()
	local name = current:getName()
	print('main:onResize:'..tostring(width)..'x'..tostring(height)..' scene:'..tostring(name))
	--SceneManager:closeScene(current)
	Application:setScreenSize(width,height)
	if type(current.resizeHandler) == 'function' then
		print("main:onResize:Invoking scene("..tostring(name)..") resizeHandler("..tostring(current.resizeHandler)..") with "..tostring(width).."x"..tostring(height))
		current.resizeHandler(width, height)
	end
	--SceneManager:openScene(name)
	setConfigScreenSize()
end

MOAIGfxDevice.setListener ( MOAIGfxDevice.EVENT_RESIZE, onResize )

function getScaledRGColor(Current, RedValue, GreenValue)
	local Percent = (Current - RedValue) / (GreenValue - RedValue) * 100.0;

	if (Percent <= 50.0) then
		if (Percent < 0.0) then Percent = 0.0 end
		return 255,255*Percent/50,0,255
	else
		if (Percent > 100.0) then Percent = 100.0 end
		return 255*(100.0-Percent)/50,255,0,255
	end
end

function formatPlatformDetails(platformOnly)
	local environment = tostring(MOAIEnvironment.devPlatform or '')
	local model = tostring(MOAIEnvironment.devManufacturer or MOAIEnvironment.devBrand or '')
	local name = tostring(MOAIEnvironment.devModel or MOAIEnvironment.devName or '')
	local platformName = tostring(MOAIEnvironment.osBrand or '')
	local platformVersion = tostring(MOAIEnvironment.osVersion or '')
	if #environment > 0 then environment = ' '..environment end
	if #model > 0 then model = ' '..model end
	if #name > 0 then if name == 'unknown' then name = '' else name = ' '..name end end
	if #platformName > 0 then platformName = ' '..platformName end
	if #platformVersion > 0 then platformVersion = ' '..platformVersion end

	local myApp = MOAIEnvironment.appDisplayName
	if not myApp or myApp == "" then myApp = "APRSISMO" end
	
	local myVersion = MOAIEnvironment.appVersion
	if not myVersion or myVersion == "" then myVersion = "" end
	if myVersion ~= "" then myVersion="("..myVersion..")" end

	local platformSize = ''
	if type(Application.viewWidth)=='number' and type(Application.viewHeight)=='number' then
		platformSize=platformSize..' '..tostring(Application.viewWidth)..'x'..tostring(Application.viewHeight)
	end
	if type(MOAIEnvironment.screenDpi)=='number' then
		platformSize=platformSize..'@'..tostring(MOAIEnvironment.screenDpi)..'dpi'
	end
	if type(config.Screen.scale)=='number' then
		platformSize=platformSize..string.format("*%.2f", config.Screen.scale)
	end
	
	local report
	if not platformOnly then
		report = myApp..myVersion..environment..model..name..platformName..platformVersion..platformSize
	else report = environment..model..name..platformName..platformVersion
	end
	return report
end
config.About.Platform = formatPlatformDetails(true)
config:addString("About", "About.Platform", "", -1, "*Unknown*")

config:addGroup("Environment", "Environment Views")
if not config.Environment then config.Environment = {} end
config:addString("Environment", "Environment.cacheDirectory", "cacheDirectory", -1, "*Unknown*")
config:addString("Environment", "Environment.documentDirectory", "documentDirectory", -1, "*Unknown*")
config:addString("Environment", "Environment.externalCacheDirectory", "externalCacheDirectory", -1, "*Unknown*")
config:addString("Environment", "Environment.externalFilesDirectory", "externalFilesDirectory", -1, "*Unknown*")
config:addString("Environment", "Environment.resourceDirectory", "resourceDirectory", -1, "*Unknown*")
config.Environment.cacheDirectory = tostring(MOAIEnvironment.cacheDirectory)
config.Environment.documentDirectory = tostring(MOAIEnvironment.documentDirectory)
config.Environment.externalCacheDirectory = tostring(MOAIEnvironment.externalCacheDirectory)
config.Environment.externalFilesDirectory = tostring(MOAIEnvironment.externalFilesDirectory)
config.Environment.resourceDirectory = tostring(MOAIEnvironment.resourceDirectory)

if type(config.lastTemps) == 'nil' then config.lastTemps = false end
if tonumber(config.lastTemps) then config.lastTemps = tonumber(config.lastTemps) end
if type(config.lastDim) == 'nil' then config.lastDim = false end
if type(config.lastLabels) == 'nil' then config.lastLabels = true end
if type(config.lastMapScale) == 'nil' then config.lastMapScale = 1 end

local mouseX = 0
local mouseY = 0
local lastX = 0
local lastY = 0

local points = { 0, 0 }
function onDraw ( index, xOff, yOff, xFlip, yFlip )
	if #points > 2048 then points = {}; lastX, lastY = 0,0 end
	local r, g, b = getScaledRGColor(#points, 2048, 0)
	MOAIGfxDevice.setPenColor(r/255,g/255,b/255,1)
    MOAIDraw.drawLine ( unpack ( points ) )
	--print('onDraw:'..tostring(#points)..' points')
end

local tapX = 0
local tapY = 0
function startTap ( downX, downY)
	tapX, tapY = downX, downY
end
function checkTap ( upX, upY)
	print(string.format('checkTap: dx=%i dy=%i', upX-tapX, upY-tapY))
	if toastLayer then
		local x,y = toastLayer:wndToWorld(upX, upY)
		local partition = toastLayer:getPartition()
		local list = { partition:propListForPoint(x,y,nil,MOAILayer.SORT_PRIORITY_DESCENDING) }
		if list then
			for k,v in ipairs(list) do
				print(string.format('toastProp%s %s @%i,%i has %s %s(%s)', tostring(toastLayer), tostring(partition), x,y, tostring(k), tostring(v), tostring(v.name)))
				if type(v.onTap) == 'function' then
					if v.onTap() then break end
				end
			end
		end
	end
	if layer then
		local x,y = layer:wndToWorld(upX, upY)
		local partition = layer:getPartition()
		local list = { partition:propListForPoint(x,y,nil,MOAILayer.SORT_PRIORITY_DESCENDING) }
		if list then
			for k,v in ipairs(list) do
				print(string.format('Prop%s %s @%i,%i has %s %s(%s)', tostring(toastLayer), tostring(partition), x,y, tostring(k), tostring(v), tostring(v.name)))
				if type(v.onTap) == 'function' then
					if v.onTap() then break end
				end
			end
		end
	end
end

function onTouch ( eventType, idx, x, y, tapCount  )
print ( string.format('onTouch:%s[%s]:%.4f,%.4f %i', tostring(eventType), tostring(idx), x, y, tapCount ))
--	mouseX, mouseY = layer:wndToWorld ( x, y )
--[[if eventType == MOAITouchSensor.TOUCH_DOWN then
		startTap(x,y)
	elseif eventType == MOAITouchSensor.TOUCH_UP then
		checkTap(x,y)
	end
	if mouseX ~= lastX or mouseY ~= LastY or eventType == MOAITouchSensor.TOUCH_DOWN then
		lastX, lastY = mouseX, mouseY
        table.insert ( points, mouseX )
		table.insert ( points, mouseY )
	end
]]
end

if MOAIInputMgr.device.touch then
	print("Initializing touch callback...")
--	MOAIInputMgr.device.touch:setCallback ( onTouch )
else print("no touch supported")
end

local leftIsDown
function onPointerEvent ( x, y )
--[[
	mouseX, mouseY = layer:wndToWorld ( x, y )
	if leftIsDown then
		--print ( string.format('onPointerEvent:%i,%i or %i,%i', x, y, mouseX, mouseY ))
		if mouseX ~= lastX or mouseY ~= LastY then
			lastX, lastY = mouseX, mouseY
			table.insert ( points, mouseX )
			table.insert ( points, mouseY )
			--print("onPointerEvent:up:mouseX:", mouseX, " mouseY:", mouseY)
		end
	end
]]
end

if MOAIInputMgr.device.pointer then
	--MOAIInputMgr.device.pointer:setCallback ( onPointerEvent )
end

function clickCallback( down )
	leftIsDown = down
	local x, y = MOAIInputMgr.device.pointer:getLoc()
	local xW, yW = layer:wndToWorld ( x, y )
	print(string.format('click at %i,%i or %i,%i vs %i,%i', x, y, xW, yW, mouseX, mouseY))
	if down then
		startTap(x,y)
	else
		checkTap(x,y)
	end
end

if MOAIInputMgr.device.mouseLeft then
	--MOAIInputMgr.device.mouseLeft:setCallback ( clickCallback )
end

--[[
local scriptDeck = MOAIScriptDeck.new ()
scriptDeck:setRect ( -64, -64, 64, 64 )
scriptDeck:setDrawCallback ( onDraw )

local prop2 = MOAIProp2D.new ()
prop2.name = "scribbles"
prop2:setDeck ( scriptDeck )
layer:insertProp ( prop2 )
]]


  print ("               Display Name : ", tostring(MOAIEnvironment.appDisplayName))
  print ("                     App ID : ", tostring(MOAIEnvironment.appID))
  print ("                App Version : ", tostring(MOAIEnvironment.appVersion))
  print ("            Cache Directory : ", tostring(MOAIEnvironment.cacheDirectory))
  print ("   Carrier ISO Country Code : ", tostring(MOAIEnvironment.carrierISOCountryCode))
  print ("Carrier Mobile Country Code : ", tostring(MOAIEnvironment.carrierMobileCountryCode))
  print ("Carrier Mobile Network Code : ", tostring(MOAIEnvironment.carrierMobileNetworkCode))
  print ("               Carrier Name : ", tostring(MOAIEnvironment.carrierName))
  print ("            Connection Type : ", tostring(MOAIEnvironment.connectionType))
  print ("               Country Code : ", tostring(MOAIEnvironment.countryCode))
  print ("                    CPU ABI : ", tostring(MOAIEnvironment.cpuabi))
  print ("               Device Brand : ", tostring(MOAIEnvironment.devBrand))
  print ("                Device Name : ", tostring(MOAIEnvironment.devName))
  print ("        Device Manufacturer : ", tostring(MOAIEnvironment.devManufacturer))
  print ("               Device Model : ", tostring(MOAIEnvironment.devModel))
  print ("            Device Platform : ", tostring(MOAIEnvironment.devPlatform))
  print ("             Device Product : ", tostring(MOAIEnvironment.devProduct))
  print ("         Document Directory : ", tostring(MOAIEnvironment.documentDirectory))
  print ("         iOS Retina Display : ", tostring(MOAIEnvironment.iosRetinaDisplay))
  print ("              Language Code : ", tostring(MOAIEnvironment.languageCode))
  print ("                   OS Brand : ", tostring(MOAIEnvironment.osBrand))
  print ("                 OS Version : ", tostring(MOAIEnvironment.osVersion))
  print ("         Resource Directory : ", tostring(MOAIEnvironment.resourceDirectory))
  print ("                 Screen DPI : ", tostring(MOAIEnvironment.screenDpi))
  print ("              Screen Height : ", tostring(MOAIEnvironment.screenHeight))
  print ("               Screen Width : ", tostring(MOAIEnvironment.screenWidth))
  print ("                       UDID : ", tostring(MOAIEnvironment.udid))



service = require("service")	-- Get the service-support set up
APRSIS = require("APRSIS")()	-- Get an APRSIS connection object
APRSIS:setStationID(config.StationID, config.PassCode)
APRSIS:setRange(config.Range)
APRSIS:setFilter(config.Filter)
APRSIS:setServerPort(config.APRSIS.Server, config.APRSIS.Port)
-- Tie the APRS layer into the APRS-IS transmitter
APRS:addTransmitListener(function(what,packet)
							APRSIS:sendPacket(config.StationID..">"..config.ToCall..",TCPIP*:"..packet)
						end)

--config:addNumber("APRSIS", "Range", "Default m/ Range", 50, 1, 999, updateFilter)
--config:addNumber("APRSIS", "APRSIS.QuietTime", "Max Idle seconds before Disconnect", 60, 0, 5*60)
--config:addBoolean("APRSIS", "APRSIS.Notify", "Connection Status Notifications", true)
--config:addString("APRSIS", "Filter", "Additional APRS-IS Filter", 256, "u/APWA*/APWM*", nil, nil, updateFilter)

-- if config.APRSIS.Enabled then APRSIS:start() end -- This is started in APRSmap

print("Running APRSIS:update ServiceCoroutine")
runServiceCoroutine(function ()
						while true do
							--print("Update APRSIS")
							APRSIS:update()
							coroutine.yield()
						end
					end)
print("Back from running CoRoutine")

BTPort = require("btport")
osmTiles = require("osmTiles")	-- This currently sets the Z order of the map

--performWithDelay( 1000, updateMemoryUsage, 0)

	print('cacheDirectory:'..tostring(MOAIEnvironment.cacheDirectory))
	print('documentDirectory:'..tostring(MOAIEnvironment.documentDirectory))
	print('resourceDirectory:'..tostring(MOAIEnvironment.resourceDirectory))

simRunning = true
simStarting = false

local lastHistogram = nil
local lastUpdateCounters = nil
local lastUpdateTimes = nil
local pauseTime = MOAISim.getDeviceTime()

MOAISim.setListener(MOAISim.EVENT_PAUSE,
--MOAISim.setListener(MOAISim.EVENT_STOP,
	function()
		print(string.format('pause=%s stop=%s', tostring(MOAISim.EVENT_PAUSE), tostring(MOAISim.EVENT_STOP)))
		config:save('Paused')
		simRunning = false
		pauseTime = MOAISim.getDeviceTime()
if MOAISim and type(MOAISim.getUpdateCounters) == 'function' then
	lastUpdateCounters = MOAISim.getUpdateCounters()
end
if MOAISim and type(MOAISim.getUpdateTimes) == 'function' then
	lastUpdateTimes = MOAISim.getUpdateTimes()
end
if MOAILuaRuntime and type(MOAILuaRuntime.getHistogram) == 'function' then
	lastHistogram = MOAILuaRuntime.getHistogram()
end
		if config.Debug.WakeUp then
			local whoFor = 'KJ4ERJ-AP'
			local text = 'sim paused, '..tostring(idleTimers)..' Timers Executed'
			local msg = string.format(':%-9s:%s', whoFor, text)
			APRS:transmit("message", msg)
		end
		idleTimers = 0
end)

local QSOs
MOAISim.setListener(MOAISim.EVENT_RESUME,
--MOAISim.setListener(MOAISim.EVENT_START,
	function()
		local whoFor = 'KJ4ERJ-AP'
		print(string.format('resume=%s start=%s', tostring(MOAISim.EVENT_RESUME), tostring(MOAISim.EVENT_START)))
		simRunning = true
		if config.Debug.WakeUp then
			local now = MOAISim.getDeviceTime()
			local elapsed = math.floor(now - pauseTime + 0.5)
			local text = 'sim resumed, '..tostring(idleTimers)..' Timers Queued in '..tostring(elapsed)..' seconds'
			local msg = string.format(':%-9s:%s', whoFor, text)
			APRS:transmit("message", msg)
			if not QSOs then QSOs = require('QSOs') end
			QSOs:newMessage("ME", whoFor, text)
			performWithDelay(1000, function() toast.new(text) end)
		end

if (config.Debug.WakeUp or config.Debug.WakeUpToast) and config.Debug.WakeUpCount > 0 then
if MOAILuaRuntime and type(MOAILuaRuntime.getHistogram) == 'function' then
	local i = 0
	performWithDelay2('WakeupHistogram', 1000, function ()
							i = i + 1
							local o = ""
							local h = MOAILuaRuntime.getHistogram()
							if (lastHistogram) then
								for k,v in pairsByKeys( h ) do
									--if k ~= "SingleStep" then
										if lastHistogram[k] then
											local d = v-lastHistogram[k]
											if string.len(k) > 5 and string.sub(k,1,4) == 'MOAI' then
												k = 'm'..string.sub(k,5)
											end
											if d > 0 then
												o = o .. ""..k.."+"..tostring(d).." "
											elseif d < 0 then
												o = o .. ""..k..""..tostring(d).." "
											end
										else
											o = o .. ""..k.."="..tostring(v).." "
										end
									--end
								end
								if o ~= "" then print("*** Objects:"..o.." ***") end
							else
								o = printableTable('ObjectHistogram',h)
							end
							lastHistogram = h
	if o and o ~= '' then
		o = tostring(i)..":"..o
		if config.Debug.WakeUp then
			local msg = string.format(':%-9s:%s', whoFor, o)
			APRS:transmit("message", msg)
			if not QSOs then QSOs = require('QSOs') end
			QSOs:newMessage("ME", whoFor, o)
		end
		if config.Debug.WakeUpToast then performWithDelay(1000, function() toast.new(o) end) end
	end
						end, config.Debug.WakeUpCount)
end

if MOAISim and type(MOAISim.getUpdateCounters) == 'function' then
	local i = 0
	performWithDelay2('WakeupCounters', 1000, function ()
							i = i + 1
							local o = tostring(i)..":"
							local c = MOAISim.getUpdateCounters()
							if (lastUpdateCounters) then
								for k,v in pairsByKeys( c ) do
									--if k ~= "SingleStep" then
										if lastUpdateCounters[k] then
											local d = v-lastUpdateCounters[k]
											if d ~= 0 then
												o = o..k.."+"..tostring(d).." "
											end
										else
											o = o..k.."="..tostring(v).." "
										end
									--end
								end
							else
								o = printableTable('UpdateCounters',c)
							end
							lastUpdateCounters = c
							local t = MOAISim.getUpdateTimes()
							if (lastUpdateTimes) then
								for k,v in pairsByKeys( t ) do
									--if k ~= "SingleStep" then
										if lastUpdateTimes[k] then
											local d = v-lastUpdateTimes[k]
											if d ~= 0 then
												o = o..k.."+"..tostring(math.floor(d*1000+0.5)).." "
											end
										else
											o = o..k.."="..tostring(math.floor(v*1000+0.5)).." "
										end
									--end
								end
							else
								o = printableTable('UpdateTimes',t)
							end
							lastUpdateTimes = t
		if config.Debug.WakeUp then
			local msg = string.format(':%-9s:%s', whoFor, o)
			APRS:transmit("message", msg)
			if not QSOs then QSOs = require('QSOs') end
			QSOs:newMessage("ME", whoFor, o)
		end
		if config.Debug.WakeUpToast then performWithDelay(1000, function() toast.new(o) end) end
						end, config.Debug.WakeUpCount)
end
end	-- config.Debug.WakeUp

		idleTimers = 0
end)

MOAISim.setListener(MOAISim.EVENT_FINALIZE,
	function()
		print('finalize')
		config:save('Finalized')
end)

local backTiming = false
local backValid = nil	-- Ignore more backs until this time

local function onMenuButtonPressed ()
	local scene = SceneManager:getCurrentScene()
	print('main:onMenuButtonPressed:scene:'..tostring(scene.name))
	if type(scene.menuHandler) == 'function' then
		scene.menuHandler()
	end
end

local function onBackButtonPressed ()
	local scene = SceneManager:getCurrentScene()

	print('main:onBackButtonPressed:scene:'..tostring(scene.name))

	if backValid and backValid > MOAISim.getDeviceTime() then
		print('suppressing redundant Back')
		return true
	elseif config:unconfigure() then
		print('Backed out of config')
	elseif type(scene.backHandler) == 'function' then
		scene.backHandler()
	elseif SceneManager:getCurrentScene().name == 'config_scene' then
		print('Force closing config!')
		SceneManager:closeScene({animation = "popOut"})
	elseif SceneManager:getCurrentScene().name == 'buttons_scene' then
		print('Backing out of Buttons')
		SceneManager:closeScene({animation="popOut"})
	elseif SceneManager:getCurrentScene().name == 'chooser_scene' then
		print('Backing out of Chooser')
		SceneManager:closeScene({animation="popOut"})
	elseif SceneManager:getCurrentScene().name == 'QSO_scene' then
		print('Backing out of QSO')
		SceneManager:closeScene({animation="popOut"})
	elseif SceneManager:getCurrentScene().name == 'QSOs_scene' then
		print('Backing out of QSOs')
		SceneManager:closeScene({animation="popOut"})
	elseif SceneManager:getCurrentScene().name == 'APRSmap' then	-- Only allowed to back out from here!
		if backTiming then
			if config.Enables.GPS and MOAIAppAndroid and type(MOAIAppAndroid.setGPSEnabled) == 'function' then
				print("setGPSEnabled(false)="..tostring(MOAIAppAndroid.setGPSEnabled(false)))
			end
			return false
		end
		performWithDelay(300, function()
			backTiming = true
			toast.new('Press Back again to exit', 2000, function() backTiming = false end)
			performWithDelay(2000, function() backTiming = false end)
			-- Return true if you want to override the back button press and prevent the system from handling it.
		end)
		print('First Back Button Suppressed!')
		return true --true to cancel back
	end
	print('main:onBackButtonPressed:Suppressing back for 1/5 second more')
	backValid = MOAISim.getDeviceTime() + 0.20	-- Ignore more backs for 1/5 second
	return true	-- This one HAS been proceesed!
end

--[[
if MOAISim and type(MOAISim.getUpdateCounters) == 'function' then
	print("Monitoring UpdateCounters")
	local l = nil
	local l2 = nil
	performWithDelay(1000, function ()
							local c = MOAISim.getUpdateCounters()
							if (l) then
								local o = ""
								for k,v in pairsByKeys( c ) do
									--if k ~= "SingleStep" then
										if l[k] then
											local d = v-l[k]
											if d ~= 0 then
												o = o .. "["..k.."]+"..tostring(d).." "
											end
										else
											o = o .. "["..k.."]="..tostring(v).." "
										end
									--end
								end
								print("*** UpdateCounts:"..o.." ***")
							else
								print(printableTable('UpdateCounters',c,'\n\t'))
							end
							l = c
							t = MOAISim.getUpdateTimes()
							if (l2) then
								local o = ""
								for k,v in pairsByKeys( t ) do
									--if k ~= "SingleStep" then
										if l2[k] then
											local d = v-l2[k]
											if d ~= 0 then
												o = o .. "["..k.."]+"..tostring(math.floor(d*1000+0.5)).." "
											end
										else
											o = o .. "["..k.."]="..tostring(math.floor(v*1000+0.5)).." "
										end
									--end
								end
								print("*** UpdateTimes:"..o.." ***")
							else
								print(printableTable('UpdateTimes',t,'\n\t'))
							end
							l2 = t
						end, 0)
end
]]

--print(printableTable('IO',io,'\n\t'))
--print(printableTable('Math',math,'\n\t'))
--print(printableTable('string',string,'\n\t'))

--[[
if MOAILuaRuntime and type(MOAILuaRuntime.getHistogram) == 'function' then
	print("Monitoring LuaRuntime Histogram")
	local l = nil
	performWithDelay(1000, function ()
							local h = MOAILuaRuntime.getHistogram()
							if (l) then
								local o = ""
								for k,v in pairs( h ) do
									--if k ~= "SingleStep" then
										if l[k] then
											local d = v-l[k]
											if d > 0 then
												o = o .. "["..k.."]+"..tostring(d).." "
											elseif d < 0 then
												o = o .. "["..k.."]"..tostring(d).." "
											end
										else
											o = o .. "["..k.."]="..tostring(v).." "
										end
									--end
								end
								if o ~= "" then print("*** Objects:"..o.." ***") end
							else
								print(printableTable('ObjectHistogram',c,'\n\t'))
							end
							l = h
						end, 0)
end
]]

if MOAILuaRuntime and MOAILuaRuntime.TRACK_OBJECTS and MOAILuaRuntime.setTrackingFlags then
	print("Tracking Objects for Histogram via "..tostring(MOAILuaRuntime.TRACK_OBJECTS))
	MOAILuaRuntime.setTrackingFlags(MOAILuaRuntime.TRACK_OBJECTS)
end

--[[
if MOAILuaRuntime and type(MOAILuaRuntime.reportHistogram) == 'function' then
	print("Monitoring LuaRuntime Histogram")
	performWithDelay(1000, function ()
							print("Reporting Histogram")
							MOAILuaRuntime.reportHistogram()
						end, 0)
end
]]

print('MOAIApp:'..tostring(MOAIApp)..' MOAIAppAndroid:'..tostring(MOAIAppAndroid)..' MOAIAppIOS:'..tostring(MOAIAppIOS))
if not MOAIApp then MOAIApp = MOAIAppAndroid; end
print('MOAIApp:'..tostring(MOAIApp)..' MOAIAppAndroid:'..tostring(MOAIAppAndroid)..' MOAIAppIOS:'..tostring(MOAIAppIOS))

if MOAIApp then
if type(MOAIApp.setListener) == 'function' then
	print("Registering MOAIApp's Back Button!")
	print('Back:'..tostring(MOAIApp.BACK_BUTTON_PRESSED)..' or '..tostring(MOAIApp["BACK_BUTTON_PRESSED"])..' Start:'..tostring(MOAIApp.SESSION_START)..' End:'..tostring(MOAIApp.SESSION_END))
	MOAIApp.setListener ( MOAIApp.BACK_BUTTON_PRESSED, onBackButtonPressed )
	MOAIApp.setListener ( MOAIApp.MENU_BUTTON_PRESSED, onMenuButtonPressed )
	
	local function printEvent(event)
		if type(MOAIApp[event]) == 'number' then
			MOAIApp.setListener(MOAIApp[event], function() print("MOAIApp."..event.." fired!") end)
		else print("No definition for MOAIApp."..event)
		end
	end
	printEvent("SESSION_START")
	printEvent("SESSION_END")
	printEvent("ACTIVITY_ON_START")
	printEvent("ACTIVITY_ON_STOP")
	printEvent("ACTIVITY_ON_DESTROY")
	printEvent("ACTIVITY_ON_RESTART")
	printEvent("EVENT_MEMORY_WARNING")
	
else	print('MOAIApp.setListener='..type(MOAIApp.setListener))
end
else print('MOAIApp='..type(MOAIApp))
end

--[[
if MOAIAppAndroid then
if type(MOAIAppAndroid.setListener) == 'function' then
	if MOAIAppAndroid.BACK_BUTTON_PRESSED then
		print("Registering MOAIAppAndroid's Back Button as "..tostring(MOAIAppAndroid.BACK_BUTTON_PRESSED))
		MOAIAppAndroid.setListener ( MOAIAppAndroid.BACK_BUTTON_PRESSED, onBackButtonPressed )
	end
	if MOAIAppAndroid.MENU_BUTTON_PRESSED then
		print("Registering MOAIAppAndroid's Menu Button as "..tostring(MOAIAppAndroid.MENU_BUTTON_PRESSED))
		MOAIAppAndroid.setListener ( MOAIAppAndroid.MENU_BUTTON_PRESSED, onMenuButtonPressed )
	end
else	print('MOAIAppAndroid.setListener='..type(MOAIAppAndroid.setListener))
end
else print('MOAIAppAndroid='..type(MOAIAppAndroid)..' No Back Button Support!')
end
]]

--[[
local function getLuaValue(v)
	if type(v) ~= 'string' then return 'nil' end
	--if type(v) == 'nil' then return 'nil' end
	local f, err = loadstring('return '..v)
	if f == nil then return 'nil' end
	local s, r = pcall(f)
	if s == false then
		print('pcall('..v..') gave '..tostring(r))
		return 'nil'
	end
	if r == nil then return 'nil' end
	return tostring(r)
end
local function testLuaValue(v)
	local r = getLuaValue(v)
	print('getLuaValue('..tostring(v)..'):'..tostring(r))
	return r
end
testLuaValue('foo.fil.this.should.be.nil')
testLuaValue('toast.bogus.field')
testLuaValue('config.Enables.GPS')
testLuaValue('config.Enables.KeepAwake')
testLuaValue('config.Filter')
testLuaValue('config.bogus.field')
]]

print('main.lua done processing!')

local versionDialogActive

local function checkNewVersion()
local URL = "http://ldeffenb.dnsalias.net/APRSISMO/*"	-- where new versions come from

	local function versionListener( task, responseCode )
		if responseCode ~= 200 then
			print ( "versionListener:Network error:"..responseCode)
		else
--[[HTTP/1.0 200 OK
X-Thread: *UNKNOWN*
Connection: close
Content-Type: application/vnd.android.package-archive
Date: Monday, 12 Aug 2013 19:51:32 GMT
Content-Length: 2853035]]
			local filename = nil
			if Application:isMobile() then
				filename = "APRSISMO%.apk"
			elseif Application:isDesktop() then
				filename = "APRSISMO%.7z"
			else	print('checkNewVersion:Unrecognized platform!')
			end
			if filename then
				local s,e,timestamp = task:getString():find(filename..".-%<%/A%>%s([%d%s]%d%s%w%w%w%s%d%d%d%d%s%d%d:%d%d:%d%d)")
				if timestamp then
					print (filename..' version is '..timestamp)
					print('last:'..tostring(config.LastAPKTimestamp)..' now:'..timestamp)
					if not config.LastAPKTimestamp then	-- virgin birth?
						config.LastAPKTimestamp = timestamp
						config:save('APK Timestamp')
					elseif config.LastAPKTimestamp ~= timestamp then
						local text = "Possible new Version:\r\n"..timestamp..'\r\nYours:'..MOAIEnvironment.appVersion..'\r\nThey will not match exactly'
						if MOAIDialog and type(MOAIDialog.showDialog) == 'function' then
							versionDialogActive = true
							MOAIDialog.showDialog('New Version', text, 'Go There', 'Not Now', 'Never', true, 
										function(result)
											versionDialogActive = false
											if result == MOAIDialogAndroid.DIALOG_RESULT_POSITIVE then
												if MOAIApp and type(MOAIApp.openURL) == 'function' then
													MOAIApp.openURL(URL)
												else toast.new("Oops, Missing MOAIApp.openURL("..type(MOAIApp.openURL)..")!")
												end
											elseif result == MOAIDialogAndroid.DIALOG_RESULT_NEUTRAL then
											elseif result == MOAIDialogAndroid.DIALOG_RESULT_NEGATIVE then
												config.LastAPKTimestamp = timestamp
												config:save('APK Timestamp')
											elseif result == MOAIDialogAndroid.DIALOG_RESULT_CANCEL then
											end
										end)
						else
							scheduleNotification(0,{alert=text})
							config.LastAPKTimestamp = timestamp
							config:save('APK Timestamp')
						end
					end
				else print ('Failed to match .APK date')
				end
			end
		end
		performWithDelay( 60*60*1000, checkNewVersion)
	end

	if versionDialogActive then
		performWithDelay( 60*60*1000, checkNewVersion)
	else
		local task = MOAIHttpTask.new ()
		task:setVerb ( MOAIHttpTask.HTTP_GET )
		task:setUrl ( URL )
		task:setTimeout ( 15 )
		task:setCallback ( versionListener )
		task:setUserAgent ( string.format('%s from %s %s',
													tostring(config.StationID),
													MOAIEnvironment.appDisplayName,
													tostring(config.About.Version)) )
		task:setVerbose ( true )
		task:performAsync ()
	end
end
performWithDelay( 30000, checkNewVersion)

local function printEvent(event)
	print(printableTable('Notification',event))
end

print('MOAINotifications:'..tostring(MOAINotifications)..' MOAINotificationsAndroid:'..tostring(MOAINotificationsAndroid)..' MOAINotificationsIOS:'..tostring(MOAINotificationsIOS))
if MOAINotifications then
	print('HAVE MOAINotifications!')
--[[
	--MOAINotifications.setListener ( MOAINotifications.REMOTE_NOTIFICATION_REGISTRATION_COMPLETE, onRemoteRegistrationComplete )
	--MOAINotifications.setListener ( MOAINotifications.REMOTE_NOTIFICATION_MESSAGE_RECEIVED, onRemoteMessageReceived )
	MOAINotifications.setListener(MOAINotifications.LOCAL_NOTIFICATION_MESSAGE_RECEIVED, printEvent)
	MOAINotifications.localNotificationInSeconds(30, MOAIEnvironment.appDisplayName..' running!',
						{title=MOAIEnvironment.appDisplayName, message="Test Message...", QSO="KJ4ERJ-AP" })
]]
else print('No MOAINotifications')
end

print('MOAIApp:'..tostring(MOAIApp)..' MOAIAppAndroid:'..tostring(MOAIAppAndroid)..' MOAINotificationsIOS:'..tostring(MOAIAppIOS))
if MOAIApp then
	print('HAVE MOAIApp!')
	--MOAIApp.share('ThisPrompt:', 'This is the subject', 'This is the text')
	--MOAIApp.openURL('http://ldeffenb.dnsalias.net/APRSISDR/*')
else print('No MOAIApp')
end

print('MOAIDialog:'..tostring(MOAIDialog)..' MOAIDialogAndroid:'..tostring(MOAIDialogAndroid)..' MOAIDialogIOS:'..tostring(MOAIDialogIOS))
if MOAIDialog then
--[[
	MOAIDialog.showDialog('Title here', 'This is the message to the user', 'Positive', 'Neutral', 'Negative', true, 
				function(e,m)
					print('e='..tostring(e)..' m='..tostring(m))  print(printableTable('MOAIDialog:e',e))
					print(string.format('Positive=%i Neutral=%i Negative=%i Cancel=%i',
						MOAIDialogAndroid.DIALOG_RESULT_POSITIVE,
						MOAIDialogAndroid.DIALOG_RESULT_NEUTRAL,
						MOAIDialogAndroid.DIALOG_RESULT_NEGATIVE,
						MOAIDialogAndroid.DIALOG_RESULT_CANCEL))
				end)
]]
end

--[[
	print("Printing /proc/self")
	for file in lfs.dir("/proc/self") do
		print( "Found file:/proc/self/" .. file )
	end
	print("Done printing /proc/self/*")
]]
	local hFile, err = io.open("/proc/self/statm","r")
	if hFile and not err then
			local xmlText=hFile:read("*a"); -- read file content
			io.close(hFile);
			local s, e, virtual, resident = string.find(xmlText, "(%d+)%s(%d+)")
			if virtual and resident then
				print ("/proc/self/statm:virt:"..tostring(virtual).." res:"..tostring(resident))
			else print("/proc/self/statm:"..xmlText)	-- virtual, working, share, text, lib, data, dt
			end
	else
			print( tostring(err) )
	end

if config.StationID == "KJ4ERJ-HB" then
	local habitat = require('habitat')
	if habitat and type(habitat.start) == 'function' then habitat:start(config) end
end

if config.StationID == "KJ4ERJ-12" or config.StationID == "KJ4ERJ-TS" or config.StationID == "KJ4ERJ-TH" or config.StationID == "KJ4ERJ-DV" then
	performWithDelay2("Objects", 10*1000, function()
									local Objects = {
"KJ4ERJ-AL>APWW10,TCPIP*:;TstOvrLap*241422z2812.14N\\07652.42WTTest Overlap }d0]NGLGIJILLLLLLLLKMKMLMLMLMLMLNLNLNLNMNMNMNG{R9DAA",
--"MHXTOR>APRS,qAO,AE5PL-WX:;MHXTOREKA*131500z3454.00N\\07655.80Wt049/026 TORNADO }a0IJMPRUMUKXHTJTMSMNLRLSKSHWFYHe9]1Y7Q@JM{DEKAA",
--"MHXTOR>APRS,qAO,AE5PL-WX:;MHXTORERA*131445z3508.40N\\07657.00Wt045/043 TORNADO }a0I_>c1d1c/]\"O5OR_>{DERAA"

--"KJ4ERJ-AP>APWW10,TCPIP*:;ALUM-PK  *011251z3537.76N\\08327.10WPAlum Cave Trailhead!wO/!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;ALUMBLUFF*011251z3538.33N/08326.75WzAlum Cave Bluffs!wSa!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;LeConte  *011251z3539.28N/08326.48WzLeConte Lodge!w=1!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;WestGate *011317z3543.95N/08331.13W-Westgate Resort!wJ6!",

--"MEGWSW>APRS,qAo,WE7U-3::NWS_CANCL:260600z,WINTER_WEATHER,ARZ026>028-035-036-048-049-058-MOZ113-115 {Q3KAA",
--"MLBWSW>APRS,qAo,WE7U-3::NWS_WARN :260600z,WINTER_WEATHER,FLC009-105 {Q3KAA",
--"MLBWSW>APRS,qAo,WE7U-3::NWS_WARN :260600z,WINTER_WEATHER,FLC009 {Q3KAA",

--"KJ4ERJ-AP>APWW10,TCPIP*:;01-TLV   *081453z3200.04N/03452.24E.Tel Aviv Airport !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;02-Jaffa *081453z3203.25N/03445.19E.Jaffa Sea Port !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;03-CasMar*081453z3230.07N/03453.99E.Caesarea Maritima !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;04-Carmel*081453z3244.64N/03502.52E.Mount Carmel (Muhraka) !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;05-Megido*081453z3234.71N/03510.72E.Megiddo aka Armageddon !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;06-Tibers*081454z3247.22N/03532.45E.Tiberias !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;07-Capern*081454z3252.84N/03534.47E.Capernaum !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;08-Tabgha*081454z3252.44N/03532.92E.Tabgha !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;09-Beatud*081454z3252.88N/03533.45E.Mount of Beatitudes !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;1-Leonard*081454z3205.15N/03446.18EHLeonardo Art !ISRAEL!!wwl!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;10-CasPhl*081454z3313.30N/03537.38E.Caesarea Philippi !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;11-Tibers*081454z3247.22N/03532.45E.Tiberias !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;2-HaGoshr*081454z3313.33N/03537.29EHHaGoshrim Hotel & Nature !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;3-Inbal  *081454z3146.23N/03513.31EHHotel Inbal !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;4-AmmanCh*081454z3158.52N/03553.68EHAmman Cham Palace Hotel !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;5-Petra  *081454z3017.48N/03527.45EHPetra Panorama Hotel !ISRAEL!",
--"KJ4ERJ-AP>APWW10,TCPIP*:;StarLndry*081454z3146.25N/03513.16E.Star Laundry Ze'ev Jabotinsky St 25 !ISRAEL!",

--"KJ4ERJ-AL>APWW10,TCPIP*:;DerDutch *241422z2719.40N\\08229.68WRDer Dutchmen!w(w!",
--"KJ4ERJ-AL>APWW10,TCPIP*:;TECHCONSW*241422z2719.13N/08226.93WEhttp://tinyurl.com/2017TechConSW!w>&!",
--"KJ4ERJ-AL>APWW10,TCPIP*:;CYSB-Air *241422z2722.87N/08233.22WHCourtyard Sarasota Bradenton Airport!w.6!",
--"KJ4ERJ-LS>APWW10,TCPIP*:;SZ-FL17-R*195313h2812.14N\\07652.42WT4 strikes }g1WJd^d^=J=Jd{!W00!",
--"KJ4ERJ-LS>APWW10,TCPIP*:;SZ-FL17-L*195556h2812.32N\\07633.33WT2 strikes }j1WJk^k^CJCJk{!W00!",
--"KJ4ERJ-LS>APZLUA,TCPIP*:;SZ-FL17-N*202836h2733.39N\\07700.20WT2 strikes }d1WCbWbW:C:Cb{!W00!",
--"KJ4ERJ-LS>APWW10,TCPIP*:;SZ-FL16  *195515h2735.92N\\07619.94WT28 strikes }d1WBoVoVGBGBo{!W00!",
--"KJ4ERJ-LS>APWW10,TCPIP*:;SZ-FL27  *195434h2756.84N\\07548.42WT2 strikes }d1W;R0R0*;*;R{!W00!",
--"KJ4ERJ-LS>APWW10,TCPIP*:;SZ-FL28  *195556h2823.89N\\07528.90WT70 strikes }d1WFXZXZ0F0FX{!W00!",
--"KJ4ERJ-LS>APZLUA,TCPIP*:;SZ-FL39  *204042h2942.82N\\07331.08WT2 strikes }d1W@XTXT0@0@X{!W00!",
--"KJ4ERJ-LS>APZLUA,TCPIP*:;SZ-FL29  *204059h2936.28N\\07412.22WT5 strikes }d1WBrVrVJBJBr{!W00!",
--"KJ4ERJ-LS>APZLUA,TCPIP*:;SZ-FM30  *204042h3038.32N\\07227.70WT25 strikes }d1WAmUmUEAEAm{!W00!",
--"KJ4ERJ-LS>APZLUA,TCPIP*:;SZ-FL27-B*204428h2758.81N\\07530.37WT1 strikes }d1W:XNXN0:0:X{!W00!"
													}
									if APRS then
										for i,o in pairs(Objects) do
											APRS:received(o)
										end
									end
								end) --, 0)
end

local radar = require('radar')
if radar and type(radar.start) == 'function' then radar:start(config) radar:setEnable(config.lastRadar) end

if config.Debug.RunProxy then
	performWithDelay(10000, function ()
	if string.sub(config.StationID,1,7) == 'KJ4ERJ-' then
		print("Starting Proxy")
		require "proxy"
	else print("no Proxy for "..string.sub(config.StationID,1,7))
	end end)
end

if Application:isDesktop() and config.StationID == "KJ4ERJ-LS" then
	performWithDelay(5000, function()
		config.Enables.Telemetry = false
		print("Requiring lightning")
		lightning = require('lightning')
	end)
end

if Application:isDesktop() and config.StationID == "KJ4ERJ-DV" then
	if false then 
		performWithDelay(5000, function()
			print("Requiring syslog")
			syslog = require('syslog')
		end)
	end
	if false then
		performWithDelay(5000, function()
			print("Requiring citywalk")
			syslog = require('citywalk')
		end)
	end
end

--[[performWithDelay(1000,function()
	local glat, glon = -0.00016667, -0.00016667
	local s = {}
	local offset = 0.01/60	-- a 0.01 minute square already offset to lower left
	table.insert(s,{lat=glat-0,lon=glon-0})
	table.insert(s,{lat=glat+offset*2,lon=glon-0})
	table.insert(s,{lat=glat+offset*2,lon=glon+offset*2})
	table.insert(s,{lat=glat-0,lon=glon+offset*2})
	table.insert(s,{lat=glat-0,lon=glon-0})
	local scale = 0.0001 -- degrees
	local temp = string.char(math.floor(math.log10(scale/.0001)*20+0.9999)+33)
	scale = math.pow(10,(temp:byte()-33)/20.0)*0.0001
	for i,p in ipairs(s) do
		local latOff, lonOff = math.floor((p.lat-glat)/scale+0.5), math.floor((glon-p.lon)/scale+0.5)
print(string.format("NULL-IS: latOff %d lonOff %d", latOff, lonOff))
		temp = temp..string.char(latOff+78, lonOff+78)
	end
	print("NULL-IS: Resulting Multi:"..temp)
end)]]

--if Application:isDesktop() and config.StationID == "KJ4ERJ-TS" then
--	performWithDelay(5000, function()
--		testrange = require('testrange')
--	end)
--end

--[[ Application:isDesktop() and config.StationID == "KJ4ERJ-TS" then
	local p1, p2, p3 = 0, 0, 1
	performWithDelay(5000, function()
		toast.new("Require telemetry",1000)
		local t = require('telemetry')
		t:definePoint("P1", "count", 0,1,0, function() p1 = p1 + 1 return p1 end)
		t:definePoint("P2", "count", 0,2,0, function() p2 = p2 + 100 while p2 > 999*2 do p2 = p2 - 999*2 end return p2 end)
		t:definePoint("P3", "count", 0,10,0, function() p3 = p3*2 while p3 > 3000 do p3 = p3 - 3000 end return p3 end)
		t:defineBit("Bit0", "on", 1, function() return 1 end)
		toast.new("telemetry.init()", 5000)
		t:init('testing',15, config.StationID..'>APZLUA,TCPIP*:')
	end)
end]]

function HasInternet()
	if not MOAIEnvironment then return true end
	if not MOAIEnvironment.connectionType then return true end
	if MOAIEnvironment.connectionType == MOAIEnvironment.CONNECTION_TYPE_NONE then return false end
	return true
end

if Application:isMobile() then
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

	local lastConnInfo = nil
	local lastConnType = nil
	local lastIPAddress = nil
	local connTypes = {[MOAIEnvironment.CONNECTION_TYPE_NONE] = 'None',
						[MOAIEnvironment.CONNECTION_TYPE_WIFI] = 'WiFi',
						[MOAIEnvironment.CONNECTION_TYPE_WWAN] = 'WWan'}
	performWithDelay2("ConnectionMonitor", 1000, function ()
		if MOAIEnvironment and MOAIEnvironment.connectionType then
			if MOAIEnvironment.connectionType ~= lastConnType then
				if (config.Debug.ShowConnections) then
					toast.new("Connection:"..(connTypes[MOAIEnvironment.connectionType] or tostring(MOAIEnvironment.connectionType)).." or "..tostring(MOAIEnvironment.NetworkType))
					lastConnType = MOAIEnvironment.connectionType
				end
	--		else print("MOAIEnvironment.connectionType still "..tostring(MOAIEnvironment.connectionType))
			end
	--	else print("MOAIEnvironment.connectionType:"..tostring(MOAIEnvironment.connectionType))
		end
		
		if MOAIEnvironment.SSID ~= '' or MOAIEnvironment.IPAddress ~= '' or MOAIEnvironment.BSSID ~= '' then
			local function iptoa(lIP)
				return string.format("%d.%d.%d.%d",
										bit.band(bit.rshift(lIP,0),255),
										bit.band(bit.rshift(lIP,8),255),
										bit.band(bit.rshift(lIP,16),255),
										bit.band(bit.rshift(lIP,24),255))
			end
			local IPAddress = MOAIEnvironment.IPAddress
			if IPAddress and tonumber(IPAddress) then
				IPAddress = iptoa(tonumber(IPAddress))
				if IPAddress ~= lastIPAddress and IPAddress ~= "0.0.0.0" then
					setSyslogIP(IPAddress, config.StationID)	-- Force a reconfiguration!
					lastIPAddress = IPAddress
				end
			end
			local newConnInfo = tostring(MOAIEnvironment.SSID).."\r\n"..tostring(IPAddress).."\r\n"..tostring(MOAIEnvironment.BSSID)
			if newConnInfo ~= lastConnInfo then
				if (config.Debug.ShowConnections) then
					toast.new(newConnInfo)
					lastConnInfo = newConnInfo;
				end
			end
		end
	end, 0)
else
	MOAIEnvironment.NetworkType = MOAIEnvironment.NetworkType or ''
	MOAIEnvironment.SSID = MOAIEnvironment.SSID or ''
	MOAIEnvironment.BSSID = MOAIEnvironment.BSSID or ''
end

--[[rformWithDelay(1000, function ()
	toast.new("Paired BT Devices:\r\n"..tostring(MOAIEnvironment.BTDevices))
end)]]

--[[
print("Absolute:"..MOAIFileSystem.getAbsoluteDirectoryPath("."))

print(printableTable("Dirs",MOAIFileSystem.listDirectories(".")))

local files = MOAIFileSystem.listFiles(".")

for i, f in pairs(files) do
	if f:match("^Cmd-.+%.xml$") then
		local xmlapi = require( "xml" ).newParser()
		local status, raw = pcall(xmlapi.loadFile, xmlapi, f, "." )
		if status then
			local use = xmlapi:simplify( raw )
			print(printableTable(f.."-use",use,"\r\n"))
			print(printableTable(f.."-child",raw.child,"\r\n"))
			print(printableTable(f.."-child[1]",raw.child[1],"\r\n"))
		else print("loadFile("..f..") Failed with "..tostring(raw))
		end
	end
end
]]

--print("main invoking TextBackground")
--temptext = TextBackground { text="tempText", layer=layer, textSize=24*config.Screen.scale }

--[[
local temps
local tCount = 10000
local rCount = tCount / 2
local nCount = tCount - rCount
local function setups()
	local start = MOAISim.getDeviceTime()
	temps = {}
	for s = 1, 2 do
		temps[s] = {}
		for t = 1, tCount do
			temps[s][t] = {}
		end
	end
	local elapsed = (MOAISim.getDeviceTime() - start) * 1000
	print(string.format("temps:Setup %.2fmsec", elapsed))
end

local function purge1()
	local start = MOAISim.getDeviceTime()
	for s = 1, #temps do
		local tr = temps[s]
		for t = 1, rCount do
			table.remove(tr,1)
		end
		if #temps[s] ~= nCount then
			print("temps:Oops:#tr="..#tr)
			break
		end
	end
	local elapsed = (MOAISim.getDeviceTime() - start) * 1000
	print(string.format("temps:purge1(table.remove) %.2fmsec", elapsed))
end

local function purge2()
	local start = MOAISim.getDeviceTime()
	for s = 1, #temps do
		local tr = temps[s]
		local n = {}
		for t = rCount+1,#tr do
			table.insert(n,tr[t])
		end
		temps[s] = n
		if #temps[s] ~= nCount then
			print("temps:Oops:#tr="..#tr)
			break
		end
	end
	local elapsed = (MOAISim.getDeviceTime() - start) * 1000
	print(string.format("temps:purge2(newTable) %.2fmsec", elapsed))
end

local function purge3()
	local start = MOAISim.getDeviceTime()
	for s = 1, #temps do
		local tr = temps[s]
		local n = 1
		for t = rCount+1,#tr do
			tr[n] = tr[t]
			n = n + 1
		end
		for t = #tr,n,-1 do
			tr[t] = nil
		end
		if #temps[s] ~= nCount then
			print("temps:Oops:#tr="..#tr)
			break
		end
	end
	local elapsed = (MOAISim.getDeviceTime() - start) * 1000
	print(string.format("temps:purge3(stepDown/nil) %.2fmsec", elapsed))
end

local function purge4()
	local start = MOAISim.getDeviceTime()
	for s = 1, #temps do
		local tr = temps[s]
		local n = 1
		for t = rCount+1,#tr do
			tr[n] = tr[t]
			n = n + 1
		end
		for t = #tr,n,-1 do
			table.remove(tr,t)
		end
		if #temps[s] ~= nCount then
			print("temps:Oops:#tr="..#tr)
			break
		end
	end
	local elapsed = (MOAISim.getDeviceTime() - start) * 1000
	print(string.format("temps:purge4(stepDown/remove) %.2fmsec", elapsed))
end

setups()
purge1()
temps = nil
MOAISim:forceGarbageCollection()

setups()
purge4()
temps = nil
MOAISim:forceGarbageCollection()

setups()
purge3()
temps = nil
MOAISim:forceGarbageCollection()

setups()
purge2()
temps = nil
MOAISim:forceGarbageCollection()

setups()
purge2()
temps = nil
MOAISim:forceGarbageCollection()
]]

--require("APRSmap")

--[[if MOAIAppAndroid then
	local lastBattery = ""
	print("Running BatteryToaster")
	performWithDelay2("BatteryToaster", 1000, function()
							local text = ""
							if type(MOAIEnvironment.BatteryStatus) ~= 'nil' then
								text = tostring(MOAIEnvironment.BatteryStatus)
							end
							if type(MOAIEnvironment.BatteryPlugged) ~= 'nil' then
								text = text.." "..tostring(MOAIEnvironment.BatteryPlugged)
							end
							if type(MOAIEnvironment.BatteryPercent) ~= 'nil' then
								text = text.." "..tostring(MOAIEnvironment.BatteryPercent)
							end
							print("BatteryToaster:"..tostring(text))
							if text ~= "" and text ~= lastBattery then
								toast.new(". "..text.." .", 5000)
								lastBattery = text
							end
						end, 0)
else print("MOAIAppAndroid="..tostring(type(MOAIAppAndroid)))
end]]

print("main all done!")

--[[
performWithDelay2("tcptest", 5000, function()

	local tcptest = require("tcptest")

				MOAICoroutine.new ():run ( function()
											tcptest.readLines("127.0.0.1", 3000)
										end)

end)
]]

--[[
	print("Printing .")
	for file in lfs.dir(".") do
		print( "Found file:./" .. file )
	end
	print("Done printing ./*")
]]

--[[
	performWithDelay2("WeatherZone", 10000, function()
				local zone = "FLZ047"
				zone = "FLC009"	-- Brevard
				zone = "FLC105" -- Polk

					local color = {192,0,0}
					require ("testshape")
					local polygon = addPolygon(zone, color)
					osmTiles:showPolygon(polygon, zone)
		end)
]]

if config.Debug.Performance then
 performWithDelay2("Performance", 10000, function ()
											if vmText then
												print(vmText)
											end
											for n, i in pairs(threads) do
												if i.runs > 0 then
													local text = string.format("%s took %.2fmsec over %d runs or %.2fmsec per (%s)", n, i.elapsed, i.runs, i.elapsed/i.runs, _VERSION)
													if text ~= i.lastText then
														print(text)
														i.lastText = text
													end
													i.lastRuns = i.runs
												end
											end
										end, 0)
else print("NOT reporting Performance, set config.Debug.Performance to enable")
end

if Application:isDesktop() then
	local function MonitorGlobals()
		local known = {}
		for k,v in pairs(_G) do
			--print(string.format("MonitorGlobals:%s(%s)", type(v), k))
			known[k] = type(v)
		end
		print("MonitorGlobals:Monitoring Globals")
		while true do
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

	MOAICoroutine.new():run(MonitorGlobals)
else
	print("Not running on desktop")
end

local ipifyAPIKey = "at_9Lp2l5RfNRdi2DhFdgG1ezJkoTJlg"

-- https://geo.ipify.org/api/v1?apiKey=at_9Lp2l5RfNRdi2DhFdgG1ezJkoTJlg&ipAddress=8.8.8.8	-- Leave off ipAddress to query yourself
-- https://geo.ipify.org/service/account-balance?apiKey=at_9Lp2l5RfNRdi2DhFdgG1ezJkoTJlg

local function newIP(IP)
	if IP == config.lastIP then
		--toast.new("External IP:"..tostring(IP), 10000)
		local lat, lon = tonumber(config.lastIPlat), tonumber(config.lastIPlon)
		if lat and lon then
			local tm = os.date('!*t')
			local header = config.StationID..">"..config.ToCall..":"
			local packet = header..APRS:ObjectHHMMSS("MY-IP", tm.hour, tm.min, tm.sec,
												{lat=lat, lon=lon, symbol='/I', comment=tostring(IP)})	-- /I = TCP/IP
			stations.packetReceived(packet)	-- put it on our local map
			print(packet)
		end
	else
		toast.new("NEW IP:"..tostring(IP))
		config.lastIP = IP
		config:save("NewIP")
		
MOAICoroutine:new():run(
	function ()
		local URL = "https://geo.ipify.org/api/v1?apiKey=at_9Lp2l5RfNRdi2DhFdgG1ezJkoTJlg"	-- External IP address information query

		local function infoListener( task, responseCode )
			if responseCode ~= 200 then
				print ( "infoListener:Network error:"..responseCode)
			else
				local info = task:getString()
				print(info)
				local json = require("json")
				local success, values = pcall(json.decode, json, info)
				if not success then
					print('IPInfo:json.decode('..values..') on:'..info)
				--local values = json:decode(content)
				elseif type(values) == 'table' then
					print(printableTable('IPInfo:json', values, "\n"))
					if type(values.location) == "table" then
						local lat, lon = tonumber(values.location.lat), tonumber(values.location.lng)
						if lat and lon then
							config.lastIPlat, config.lastIPlon = lat, lon
							config:save("NewIPLatLon")
	local tm = os.date('!*t')
	local header = config.StationID..">"..config.ToCall..":"
	local packet = header..APRS:ObjectHHMMSS("MY-IP", tm.hour, tm.min, tm.sec,
										{lat=lat, lon=lon, symbol='/I', comment=tostring(values.ip)})	-- /I = TCP/IP
	print(packet)
	stations.packetReceived(packet)	-- put it on our local map

						else
							print(printableTable("IPInfo.location", values.location))
						end
					end
				end
			end
		end

		local task = MOAIHttpTask.new ()
		task:setVerb ( MOAIHttpTask.HTTP_GET )
		task:setUrl ( URL )
		task:setTimeout ( 15 )
		task:setCallback ( infoListener )
		task:setVerbose ( true )
		task:performAsync ()
	end)
	
	end
end


APRSIS:addConnectedCallback(function (why)
								if why then	-- We got connected, we must have network
								
MOAICoroutine:new():run(
	function ()
		local URL = "https://api.ipify.org"	-- External IP address query

		local function addressListener( task, responseCode )
			if responseCode ~= 200 then
				print ( "addressListener:Network error:"..responseCode)
			else
				local externalIP = task:getString()
				newIP(externalIP)
			end
		end

		local task = MOAIHttpTask.new ()
		task:setVerb ( MOAIHttpTask.HTTP_GET )
		task:setUrl ( URL )
		task:setTimeout ( 15 )
		task:setCallback ( addressListener )
		task:setVerbose ( true )
		task:performAsync ()
	end)
	
								print("connectedCallback:"..tostring(why))
							end
						end)

-- local mqtt = require("mqtt")
