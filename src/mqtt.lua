local socket=require"socket"	-- For gettime()

local function TraceBack(start,stop)
	local result = ""
	for s=start, stop, 1 do
		local info = debug.getinfo( s, "Sl" )
		if not info then break end
		local where = info.source..':'..info.currentline
		if where:sub(1,1) == '@' then where = where:sub(2) end
		if #result > 0 then result = result.."<-"..where
		else result = where
		end
	end
	return result
end

local SavedTopics = {}

local function publishIfChanged(mqtt_client, topic, value, retain)
	if SavedTopics[topic] ~= value then
		print("Publishing "..topic.."="..value)
		if mqtt_client.connected then
			local failed = mqtt_client:publish(topic, value, retain)
			if failed then
				print("Publish Failed: "..tostring(failed))
			else
				SavedTopics[topic] = value
				return true
			end
		else
			print("Cannot Publish, MQTT Not Connected")
		end
	end
	return false
end

local function displayDate(when)
	local value = tonumber(when)
	if not value then return tostring(when) end
	if value == 0 then return "" end
	local now = os.date("*t", os.time())
	local there = os.date("*t", value)
	if now.year == there.year and now.month == there.month and now.day == there.day then
		value = os.date("%H:%M:%S",value)
	else value = os.date("%Y%m%d %H:%M:%S",value)
	end
	return value
end

local function displayElapsed(elapsed)
	if elapsed == 0 then return "now" end
	if elapsed < 0 then return "future" end
	local seconds = elapsed % 60
	local minutes = math.floor(elapsed/60) % 60
	local hours = math.floor(elapsed/60/60) % 24
	local days = math.floor(elapsed/60/60/24)
	local result = ""
	if days > 0 then result = result..tostring(days).."d " end
	if hours > 0 then result = result..tostring(hours).."h " end
	if minutes > 0 then result = result..tostring(minutes).."m " end
	if seconds > 0 then result = result..tostring(seconds).."s" end
	return result
end

local function callback(
  mqtt_client,	-- client handle
  topic,    -- string
  message)  -- string

	print(string.format("topic:%s message:%s", topic, message))
	
--	naylor/13625840/temp/4/1 17.8125@1593793239.949

	if topic == "naylor/13625840/temp/4/1" then
		local temp, when = string.match(message,"^([%d%.]+)@(.+)$")
		print(string.format("temp:%s when:%s", temp, when))
		if tonumber(temp) then
			temp = tonumber(temp)
			temp = temp/5*9+32
			print(string.format("%f F when:%s", temp, when))
			if not NaylorTemp then NaylorTemp = {Pkts=0, When=0, F=temp} end
			NaylorTemp.F = temp
			NaylorTemp.Pkts = NaylorTemp.Pkts+1
			NaylorTemp.When = math.floor(tonumber(when) or os.time())
		else print(string.format("non-number(%s) from %s", tostring(temp), message))
		end
	end
  
end

local function main()

	local MQTT = require("paho.mqtt")

	local args = {}
	args.id = tostring(config.StationID).."-MQTT"
	args.host = "test.mosquitto.org"
	args.port = 1883
	args.debug = false
	args.keepalive = 10

	if (args.debug) then MQTT.Utility.set_debug(true) end

	if (args.keepalive) then MQTT.client.KEEP_ALIVE_TIME = args.keepalive end

	local mqtt_client
	print("Establishing mqtt_client")
	mqtt_client = MQTT.client.create(args.host, args.port, function (topic, message) return callback(mqtt_client, topic, message) end)

	MOAICoroutine.new ():run ( runTimers, mqtt_client, output )

	while true do
		local error_message = nil
		while (error_message == nil) do

			if mqtt_client.connected then
				error_message = mqtt_client:handler()
			else
				local connectFailed
				print("Connecting to MQTT server at "..args.host)
				if (args.will_message == "."  or  args.will_topic == ".") then
				  error_message = mqtt_client:connect(args.id)
				else
				  error_message = mqtt_client:connect(args.id, args.will_topic, args.will_qos, args.will_retain, args.will_message)
				end
				if error_message then
					print("MQTT server Connect failed: "..tostring(error_message))
				else
					print("MQTT server Connected ")
					mqtt_client:subscribe({"naylor/#"})
--					mqtt_client:publish(statusTopic, "online", true)
				end
			end
			coroutine.yield ()
		end
		if (error_message == nil) then
		--  mqtt_client:unsubscribe({args.topic})
		  mqtt_client:destroy()
		else
		  print(error_message)
		  if mqtt_client.connected then
		    print("Disconnecting due to error")
			mqtt_client:disconnect()	-- this clears mqtt_client.connected
		  else print("Already not connected on error")
		  end
		  SavedTopics = {}	-- Clear published topic memory
		end
	end
end

MOAICoroutine.new ():run ( main )

