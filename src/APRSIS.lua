-- Look for CRPTOR for hard-coded weather polygon test

local APRSIS = { VERSION = "0.0.1" }

local debugging = false

--local toast = require("toast");

local packetCount = 0

function APRSIS:getPacketCount()
	return packetCount
end

local appName, appVersion = "APRSIS", "*unknown*"

function APRSIS:setAppName(name, version)
	appName = name or appName
	appVersion = version or appVersion
end

local function addCallback(callbacks, callback)
	if type(callback) == 'function' then
		if not callbacks then callbacks = {} end
		callbacks[callback] = true
	end
	return callbacks
end

local function invokeCallbacks(callbacks, ...)
	if callbacks then
		for callback in pairs(callbacks) do
			if debugging then
				callback(unpack(arg))
			else
				local status, text = pcall(callback, unpack(arg))
				if not status then
					print('APRSIS:callback:'..tostring(text))
				end
			end
		end
	end
end

function APRSIS:addPacketCallback(callback)	-- is passed a single received APRS packet + self
	self.packetCallbacks = addCallback(self.packetCallbacks, callback)
end

function APRSIS:addConnectedCallback(callback)
	self.connectedCallbacks = addCallback(self.connectedCallbacks, callback)
end

function APRSIS:addStatusCallback(callback)
	self.statusCallbacks = addCallback(self.statusCallbacks, callback)
end

function APRSIS:updateStatus(status)
	if self.status ~= status then
		self.status = status
--print("APRSIS:status:"..tostring(status))
		invokeCallbacks(self.statusCallbacks, status)
	end
end

function APRSIS:triggerReconnect(why, delay)
	serviceWithDelay('Reconnect', tonumber(delay) or 0, function() self:closeConnection(why or "Reconnect") end)
end

function APRSIS:getPortName()
	return "APRS-IS("..tostring(self.clientServer)..")"
end

local socket = require("socket")

local function timedConnection()
--print('timedConnection:client='..tostring(self.client)..' connecting='..tostring(clientConnecting)..' server='..tostring(self.clientServer))
	if config.APRSIS.Enabled then
		if not self.client then
			local status, text = pcall(getConnection)
			if not status then
				print('getConnection:'..tostring(text))
			end
--		else
--			local text = os.date("%H:%M:%S:")..tostring(self.clientServer)..' '..tostring(clientConnecting)
--			print(text)
		end
--	else
--		local text = os.date("%H:%M:%S:APRS-IS Disabled!")
--		print(text)
	end
	serviceWithDelay('timedConnection', 60*1000, timedConnection)
end

function APRSIS:closeConnection(why)
	print('closeConnection('..why..')')
	if self.client then
		--setSyslogIP(false)	-- in main.lua (just in case our IP address changed)
		self.client:close()	-- Close it down
		self.client = nil	-- and clean it up so getConnection will recover
		self.connected = nil
		self.clientServer = nil
		invokeCallbacks(self.connectedCallbacks, nil)
		print("APRS-IS Lost("..tostring(why)..")")
--[[
		if not config.APRSIS.Notify then
			toast.new(alert, 2000)
		else
			local options = { alert = alert, --badge = #notificationIDs+1, --sound = "???.caf",
								custom = { name="flushClient", Verified=Verified } }
			scheduleNotification(0,options)
		end
]]
		self.nextConnection = os.time() + 10	-- Don't try again for 10 seconds
	end
end

local function getLuaMemory()
	if type(MOAISim.getMemoryUsagePlain) == "function" then
		return MOAISim.getMemoryUsagePlain()
	end
	local m = MOAISim.getMemoryUsage()
	return m.lua or 0
end

function APRSIS:flushClient()
	local packetInfo = nil
	if self.client then
		local rcvTime, callTime, gcTime = 0, 0, 0
		local count = 0
		local startTime = MOAISim.getDeviceTime()
		local maxTime = startTime + (1.0/30.0)
		local mStart = getLuaMemory()
		local gotoStation
		local readable, writeable, err = socket.select({ self.client }, nil, 0)
		if err and err ~= "timeout" then print('client.select('..tostring(self.client)..' returned '..tostring(err).." readable:"..tostring(readable)) end
		if readable and #readable > 0 then
			--print(tostring(#readable)..' readable sockets!  is '..tostring(self.client)..'=='..tostring(readable[1])..'?')
			if readable[1] == self.client then
				repeat
					local rcvStart = MOAISim.getDeviceTime()
					if rcvStart > maxTime then
						print(string.format("APRSIS:flushClient:Too Long Receiving (%.2fms), residual(%s)",
											(rcvStart-startTime)*1000, tostring(self.residualReceived)))
						break
					end	-- Don't spend too long receiving!
					local line, err, residual = self.client:receive('*l')
					if line then
						if self.residualReceived and #self.residualReceived > 0 then
							line = self.residualReceived..line	-- add back in what we had on the last timeout
							self.residualReceived = nil	-- and clear it out since we just used it!
						end
--local org, path, packet = line:match('(.+)>(.+):(.+)')
--if not org then print("flushClient:after["..tostring(lastRCount).."]received["..tostring(count).."]:"..line)
--else print("org["..tostring(count).."]:"..tostring(org).." path:"..tostring(path).." packet:"..tostring(packet))
--end
						count = count + 1
						--lastRCount = count
						packetCount = packetCount + 1
						invokeCallbacks(self.packetCallbacks, line, self)
--				local gcStart = MOAISim.getDeviceTime()
--				collectgarbage("step")
--				gcTime = gcTime + (MOAISim.getDeviceTime()-gcStart)
					else
						if #residual then
							if not self.residualReceived then
								self.residualReceived = residual
							else
								self.residualReceived = self.residualReceived..residual
							end
						end
						--if residual and residual ~= "" then print("flushClient:err:"..tostring(err).." residual:"..tostring(residual)) end
						if err ~= 'timeout' then
							self:closeConnection('Receive Error:'..err)
						end
					end
				until not line
			else
				self:closeConnection("Client Socket not Readable")
			end
		end
		
		if self.client then
			local mEnd = getLuaMemory()
			local mDelta = (mEnd - mStart) / 1024
			local thisTime = MOAISim.getDeviceTime()
			local text = string.format('%i Packets in %.2fms(%.2f+%.2f) %.2fK',
										count, (thisTime-startTime)*1000,
										rcvTime*1000, callTime*1000, mDelta)
			--print(text)
			local idle = ""
			if lastReceive then idle = ' Idle '..(math.floor((thisTime-lastReceive)*1)/1)..'s' end
			if count > 0 then
				lastPackets = text
				self:updateStatus(lastPackets..idle)
				lastIdle = idle
			elseif idle ~= lastIdle then
				self:updateStatus((lastPackets or "")..idle)
				lastIdle = idle
			end

			--lwdtext:setString ( text );
			--lwdtext:fitSize()
			--lwdtext:setLoc(Application.viewWidth/2, 75*config.Screen.scale)

--[[
			if lwdtext then
				if not lwdtext.touchup then
					lwdtext.touchup = true
					lwdtext:addEventListener("touchUp",
								function()
									print("lwdtext touched!")
									local text = tostring(self.clientServer)..' '..tostring(clientConnecting)
									if MOAIEnvironment.SSID and MOAIEnvironment.SSID ~= "" then
										text = text.."\nWiFi:"..MOAIEnvironment.SSID
									end
									if MOAIEnvironment.BSSID and MOAIEnvironment.BSSID ~= "" then
										text = text.."\nAP:"..MOAIEnvironment.BSSID
									end
									toast.new(text)
								end)
				end
			end
]]

			if count > 0 then
				lastReceive = thisTime
			elseif lastReceive
			--and config.APRSIS.QuietTime > 0
			and (thisTime-lastReceive) > 60 then
				text = string.format('No Data in %i/%is',
												math.floor((thisTime-lastReceive)),
												60)
				self:closeConnection(text)
				lastReceive = nil
			end
		else
			self:updateStatus("APRS-IS Lost")
			--flushStatus.text = "APRS-IS Connection Lost"
			lastReceive = nil
		end
	else
		print ('flushClient: No Client Connection')
	end
end

function APRSIS:sendPacket(packet)
	print ('APRSIS:sendPacket:'..packet)
	if self.client then
		local n, err = self.client:send(packet..'\r\n')
		if type(n) ~= 'number' or n == 0 then
			self:closeConnection('sendPacket Error:'..tostring(err))
			return 'Send Error'
		end
		return nil
	end
	return 'No Client Connection'
end

function APRSIS:formatFilter()
	local range = tonumber(self.Range) or 50
	local filter = self.Filter or "u/APWA*/APWM*/APWW*"
	if range >= 1 then
		--return string.format('r/%.2f/%.2f/%i m/%i %s', myStation.lat, myStation.lon, range, range, filter)
		return string.format('m/%i %s', range, filter)
	elseif #filter > 0 then
		return filter
	else return 'p/KJ4ERJ'	-- hopefully not too many people get this!
	end
end

function APRSIS:setRange(range)
	if range ~= self.Range then
		self.Range = range
		self:sendFilter(true)
	end
end

function APRSIS:setFilter(filter)
	if filter ~= self.Filter then
		self.Filter = filter
		self:sendFilter(true)
	end
end

function APRSIS:sendFilter(ifChanged)
	if self.client then
		if myStation.lat ~= 0.0 or myStation.lon ~= 0.0 then
			local filter = self:formatFilter()
			if filter ~= self.lastFilter or not ifChanged then
				self.ackFilter = self.ackFilter or 1
				--filter = filter..' g/BLT p/K/N/W'	-- Temporary hack!
				local msg = string.format('%s>APWA00,TCPIP*::SERVER   :filter %s{%s', self.StationID, filter, self.ackFilter)
				msg = '#filter '..filter	-- send to SERVER doesn't work on non-verified connections :(
				local n, err = self.client:send(msg..'\r\n')
				if type(n) ~= 'number' or n == 0 then self:closeConnection('sendFilter Error:'..tostring(err)) end
				self.ackFilter = self.ackFilter + 1
				if self.ackFilter > 9999 then self.ackFilter = 1 end
				print ('sendFilter:'..msg)
				filtered = true
				self.lastFilter = filter
			else
				--print('sendFilter:Suppressed Redundant Filter:'..filter)
			end
		end
	end
end

function APRSIS:clientConnected()
	if self.client then
		--Get IP and Port from client
		local ip, port = self.client:getsockname()
		--Print the ip address and port to the terminal
		print("APRSIS@"..ip..":"..port.." Remote: "..tostring(self.client:getpeername()))
		self.connected = self.client:getpeername()
		--setSyslogIP(ip, self.StationID)	-- in main.lua
		invokeCallbacks(self.connectedCallbacks, self.clientServer)
		
		print("APRSIS:back from connectedCallbacks with appVersion "..tostring(appVersion))
	
		self.client:settimeout(0)	-- no timeouts for instant complete
		self.client:setoption('keepalive',true)
		self.client:setoption('tcp-nodelay',true)
		local myVersion = appVersion:gsub("(%s)", "-")

		local n, err
		local filter = self:formatFilter()
		local logon = string.format('user %s pass %s vers %s %s filter %s',
									tostring(self.StationID), tostring(self.PassCode),
									tostring(appName), tostring(myVersion), tostring(filter))
print(logon)
		n, err = self.client:send(logon..'\r\n')
print("logon sent:"..type(n)..' '..tostring(n))
		if type(n) ~= 'number' or n == 0 then
			self:closeConnection('sendLogon Error:'..tostring(err))
		end
--[[		local homeIP, text = socket.dns.toip('ldeffenb.dnsalias.net')
		if not homeIP then
			toast.new("dns.toip(ldeffenb.dnsalias.net) returned "..tostring(text))
		else toast.new('ldeffenb.dnsalias.net='..tostring(homeIP))
		end]]
	else
		print ('Failed to connect to the APRS-IS')
	end
end

function APRSIS:checkClientConnect()
	local elapsed = (MOAISim.getDeviceTime() - self.startTime)*1000
	--print('checkClientConnect('..tostring(self.master)..') elapsed '..tostring(elapsed)..'ms')
	local readable, writeable, err = socket.select(nil, { self.master }, 0)
	if err and err ~= "timeout" then print('master.select('..tostring(self.master)..' returned '..tostring(err).." writeable:"..tostring(writeable)) end
	if writeable and #writeable > 0 then
		print(tostring(#writeable)..' writeable sockets!  is '..tostring(self.master)..'=='..tostring(writeable[1])..'?')
		if writeable[1] == self.master then
			self.client = self.master
			text = 'good@'..tostring(self.connecting)..' '..tostring(math.floor(elapsed))..'ms'
			self.clientServer = self.connecting..' ('..tostring(self.client:getpeername()).."<"..tostring(self.client:getsockname())..')'
			self.connecting = nil
			self:clientConnected()
		else
			self.master:close()
			self.connecting = nil
			self:updateStatus("Master Socket not Writeable")
			text = 'Fail1@'..tostring(ip)..':'..tostring(port)..' '..tostring(math.floor(elapsed))..'ms'
			--flushStatus.text = "APRS-IS Connect Failed in "..tostring(elapsed)..'ms'
		end
	elseif elapsed > 30*1000 then
		print('Giving up and closing '..tostring(self.master)..' after '..tostring(math.floor(elapsed))..'ms')
		self.connecting = nil
		self.master:close()
		text = 'Fail2@'..tostring(ip)..':'..tostring(port)..' '..tostring(math.floor(elapsed/1000))..'s'
		self:updateStatus("APRS-IS Connect Timeout")
		--flushStatus.text = "APRS-IS Connect Failed in "..tostring(elapsed)..'ms'
	else
		local delay = math.min(elapsed/4, 1000)
		self:updateStatus(string.format("APRS-IS Connecting %d/%d...", math.floor(elapsed/1000), 30))
	end
end

function APRSIS:getConnection()

	if self.nextConnection and os.time() < self.nextConnection then
		local text = string.format("Delay %d seconds", self.nextConnection-os.time())
		self:updateStatus(text)
		return
	end

print('getConnection:client='..tostring(self.client)..' connecting='..tostring(self.connecting))

--Connect to the client
	if not self.client and not self.connecting then
	
		if not HasInternet() then
			self:updateStatus("No Internet")
			return
		end
	
		print ('Connecting to the APRS-IS')
		if self.Server and self.Port then
			self.connecting = self.Server..':'..self.Port
			--lastStation.text = config.StationID
			text = 'Connecting@'..tostring(self.connecting)
			print(text)
			self.startTime = MOAISim.getDeviceTime()
			self.master = socket.tcp()	-- Get a master socket
				--client = socket.connect(config.APRSIS.Server, config.APRSIS.Port)
				self.master:settimeout(0)	-- No timeouts on this socket
				print ('REALLY Connecting to the APRS-IS')
			local i, err = self.master:connect(self.Server, self.Port)
			if i then	-- Must have accepted it
				print('connect('..tostring(self.master)..') initiated with '..tostring(i)..':'..tostring(err))
			else
				print('connect('..tostring(self.master)..') failed with '..tostring(err))
				if err == 'timeout' then

				else
					self.master:close()
					text = 'Fail3@'..tostring(self.connecting)..' '..tostring(err)
					print(text)
					self:updateStatus(err)
					self.connecting = nil
				end
			end
			print ('Connect initiated with '..tostring(self.connecting))
		end	-- if Server and Port
	end	-- if not client

end

function APRSIS:main()
	while true do
		local update = string.format("APRSIS:%s enabled:%s connected:%s connecting:%s client:%s", tostring(self), tostring(self.enabled), tostring(self.connected), tostring(self.connecting), tostring(self.client))
		if update ~= self.lastUpdate then
			print(update)
			self.lastUpdate = update
		end

		if self.enabled then
			if not self.connected then
				if not self.connecting then
					self:getConnection()
				else
					self:checkClientConnect()
				end
			else
				self:flushClient()
			end
		elseif self.connected then
			self:closeConnection("disabled")
		end
		coroutine.yield()
	end
end

function APRSIS:update()
	coroutine.resume(self.coRoutine)
end

function APRSIS:setStationID(stationID, passcode)
	if self.StationID ~= stationID or self.PassCode ~= passcode then
		if self.connected then
			self:closeConnection("setStationID")
		end
	end
	self.StationID = stationID
	self.PassCode = passcode
end

function APRSIS:setServerPort(server, port)
	if self.StatiServeronID ~= server or self.Port ~= port then
		if self.connected then
			self:closeConnection("setServerPort")
		end
	end
	self.Server = server
	self.Port = port
end

function APRSIS:stop()
	if self.connected then
		self:closeConnection("stop")
	end
	self.enabled = false
end

function APRSIS:start()
	self.enabled = true
end

--[[
local APRS = require("APRS")
APRS:addTransmitListener(function(what,packet)
							APRSIS:sendPacket(config.StationID..">"..config.ToCall..",TCPIP*:"..packet)
						end)
]]

return function ()
	local new = { }
	for k,v in pairs(APRSIS) do
		new[k] = v
	end
	new.coRoutine = coroutine.create(function() new.main(new) end)
	return new
end
