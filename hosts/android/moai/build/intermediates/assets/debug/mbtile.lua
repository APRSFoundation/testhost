local luasql = require("luasql")

local MBTile = {}
MBTile.__index = MBTile

setmetatable(MBTile, {
  __call = function (cls, db, ...)
	if not cls.instances then cls.instances = {} end
	if cls.instances[db] then
		print("MBTile:Returning Existing Instance for "..db)
		return cls.instances[db]
	end
	print("MBTile:Making New Instance for "..db)
    local self = setmetatable({}, cls)
    cls.instances[db] = self:_init(db, ...)
    return cls.instances[db]
  end,
})

function MBTile:getMetaValue(key)
	local cur, err = self.conn:execute("select value from metadata where name='"..key.."'")
	if cur then
		local value = cur:fetch()	-- Get the actual value
		cur:close() -- already closed because all the result set was consumed (but this doesn't hurt)
		return value
	else print("sqlite:No "..key.." metadata in "..self.db.." err:"..tostring(err))
	end
	return nil
end

function MBTile:setMetaValue(key, value)
	local cur, err = self.conn:execute("update metadata set value='"..value.."' where name='"..key.."'")
	if cur then
		print("Update MetaValue("..key..") to("..value..") returned "..tostring(cur))
		if tonumber(cur) == 1 then
			return true
		else return false
		end
	else print("sqlite:Update "..key.." metadata in "..self.db.." err:"..tostring(err))
	end
	return false
end

function MBTile:_init(db)
	local err
	self.db = db
	self.env, err = luasql.sqlite3()
	if not self.env then return nil, err end
	self.conn, err = self.env:connect(db, mode == "r" and "READONLY" or "")
	if not self.conn then
		self.env:close()
		return nil, err
	end

	print("sqlite:Got database connection to "..db)
	self.name = self:getMetaValue("name")
	if not self.name then
		self.conn:close()
		self.env:close()
		self.env, self.conn = nil, nil
		return nil, "Non-MBTiles Database"
	end
	self.MetaFormat = self:getMetaValue("MetaFormat")
	self.URLFormat = self:getMetaValue("URLFormat")
	if self.URLFormat then
		local remainder = self.URLFormat:match("^http\://ldeffenb\.dnsalias\.net:6360(.+)$")
		if remainder then
			self.URLFormat = "http://ldeffenb.dnsalias.net:14160"..remainder
			if self:setMetaValue("URLFormat", self.URLFormat) then
				toast.new("Corrected "..db.." URLFormat to "..self.URLFormat)
			else toast.new("Failed To Update URLFormat in "..db)
			end
		else print("URLFormat("..self.URLFormat..") not ldeffenb in "..db)
		end
	end
	self.bounds = self:getMetaValue("bounds")
	if self.bounds then
		MOAICoroutine.new():run(function()
			local timer = MOAITimer.new()
			timer:setSpan(1)	-- 1 second delay
			MOAICoroutine.blockOnAction(timer:start())

			function mysplit(inputstr, sep)
					if sep == nil then
							sep = "%s"
					end
					local t={} ; i=1
					for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
							t[i] = str
							i = i + 1
					end
					return t
			end
			local b = mysplit(self.bounds,",")
			print(printableTable(db,b))
			if #b == 4 then	-- left, bottom, right, top
				self.min_lat = (b[2])
				self.max_lat = (b[4])
				self.min_lon = (b[1])
				self.max_lon = (b[3])
				print(string.format("Bounds(%s) are %s->%s %s->%s", db, self.min_lat, self.max_lat, self.min_lon, self.max_lon))
			end
		end)
	end

	local start = MOAISim.getDeviceTime()
	local cur, err = self.conn:execute("SELECT zoom_level, count(*) as count, min(tile_column) as min_col, max(tile_column) as max_col, min(tile_row) as min_row, max(tile_row) as max_row from tiles group by zoom_level order by zoom_level")
	if cur then
		local row = cur:fetch({},"a")
		self.contents = {}
		while row do
			self.contents[row.zoom_level] = {count=row.count,
										max_y=(2^row.zoom_level)-row.min_row-1,
										min_y=(2^row.zoom_level)-row.max_row-1,
										min_x=row.min_col,
										max_x=row.max_col }
			--[[print(string.format("sqlite:zoom:%i Count:%i Rows:%i-%i Cols:%i-%i",
								row.zoom_level, row.count,
								row.min_row, row.max_row,
								row.min_col, row.max_col))]]
			row = cur:fetch({},"a")
		end
		cur:close() -- already closed because all the result set was consumed	
		local elapsed = (MOAISim.getDeviceTime()-start)*1000
		print("Count took "..tostring(elapsed).."msec")
		self.contents.name = self.name
		self.contents.elapsed = elapsed
	end
	return self
end

function MBTile:getBlob(n,x,y,z)
	local blob = nil

	if self.env and self.conn then
		local row = (2^z)-y-1
		local zc = self.contents and self.contents[z] or nil

		if not zc
		or (y>=zc.min_y and y<=zc.max_y
			and x>=zc.min_x and x<=zc.max_x) then	-- Is it at least in range of the contents?
			-- retrieve a cursor
			local cur, err = self.conn:execute("SELECT tile_data from tiles where zoom_level="..tostring(z).." and tile_row="..tostring(row).." and tile_column="..tostring(x))
			if cur then
				-- print all rows, the rows will be indexed by field names
				blob = cur:fetch ()
				cur:close() -- already closed because all the result set was consumed	
--				if blob then
--					print("sqlite:Got "..tostring(#blob).." bytes for "..tostring(z).."/"..tostring(x).."/"..tostring(y))
--				else print("sqlite:no row for "..tostring(z).."/"..tostring(x).."/"..tostring(y))
--				end
			else print("sqlite:Got NIL cursor, err="..tostring(err))
			end
		end
	end

	return blob
end

function MBTile:checkTile(n,x,y,z)
	local start = MOAISim.getDeviceTime()

	local file = string.format('%s/%i/%i/%i.png', self.name, z, x, y)
	if not self.tileCache then
		self.tileCache = {}
		setmetatable(self.tileCache, { __mode = 'v' })
	end
	if self.tileCache[file] then
		local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
		--print("sqlite:checkTile "..tostring(n).." for "..tostring(z).."/"..tostring(x).."/"..tostring(y).." CACHE took "..tostring(elapsed).." msec")
		return true
	end
	
	return self:getBlob(n,x,y,z) ~= nil
end

function MBTile:getTileImage(n,x,y,z)
	local start = MOAISim.getDeviceTime()

	local file = string.format('%s/%i/%i/%i.png', self.name, z, x, y)
	if not self.imageCache then
		self.imageCache = {}
		setmetatable(self.imageCache, { __mode = 'v' })
	end
	if self.imageCache[file] then
		local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
--		print("sqlite:getTile "..tostring(n).." for "..tostring(z).."/"..tostring(x).."/"..tostring(y).." CACHE took "..tostring(elapsed).." msec")
		return self.imageCache[file]
	end

	local blob = self:getBlob(n,x,y,z)
	if blob then
		local buffer = MOAIDataBuffer.new()
		buffer:setString(blob)


		local image = MOAIImage.new()
		image:loadFromBuffer(buffer)

		local width, height = image:getSize()
		if width ~= 256 or height ~= 256 then
			print('getTile('..tostring(z).."/"..tostring(x).."/"..tostring(y)..') is '..tostring(width)..'x'..tostring(height)..' bytes:'..tostring(#blob))
			image = nil
		end
		--local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
		--print(string.format("getTileImage:%d %d %d in %dmsec", x, y, z, elapsed))
		self.imageCache[file] = image
		return image
	end
	return nil
end

function MBTile:getTileTexture(n,x,y,z)
	local start = MOAISim.getDeviceTime()

	local file = string.format('%s/%i/%i/%i.png', self.name, z, x, y)
	if not self.tileCache then
		self.tileCache = {}
		setmetatable(self.tileCache, { __mode = 'v' })
	end
	if self.tileCache[file] then
		local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
--		print("sqlite:getTile "..tostring(n).." for "..tostring(z).."/"..tostring(x).."/"..tostring(y).." CACHE took "..tostring(elapsed).." msec")
		return self.tileCache[file]
	end

	local blob = self:getBlob(n,x,y,z)
	if blob then
		local buffer = MOAIDataBuffer.new()
		buffer:setString(blob)


		local image = MOAITexture.new()
		image:load(buffer, file)
--		local image = MOAIImage.new()
--		image:loadFromBuffer(buffer)


		local width, height = image:getSize()
		if width ~= 256 or height ~= 256 then
			print('getTile('..tostring(z).."/"..tostring(x).."/"..tostring(y)..') is '..tostring(width)..'x'..tostring(height)..' bytes:'..tostring(#blob))
			image = nil
--		else image = Sprite { texture = image, left=0, top=0 }
		end
		--local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
		--print(string.format("getTile(Texture):%d %d %d in %dmsec", x, y, z, elapsed))
--		print("sqlite:getTile "..tostring(n).." for "..tostring(z).."/"..tostring(x).."/"..tostring(y).." took "..tostring(elapsed).." msec")
		self.tileCache[file] = image
--		if not self.purgeList then self.purgeList = List.new()
--		self.purgeList:pushright(file)
--		if self.purgeList:getCount() > 500 then
--			local temp = self.purgeList:popleft()
--			print("sqlite:getTile:Purging "..file)
--			self.tileCache[file] = nil
--		end
		return image
	end
	return nil
end

function MBTile:saveTile(n,x,y,z,buffer)

	local start = MOAISim.getDeviceTime()

	local blob = nil

	if self.env and self.conn then
--		print("sqlite:saveTile "..tostring(n).." for "..tostring(z).."/"..tostring(x).."/"..tostring(y).." from buffer")

			local start2 = MOAISim.getDeviceTime()

			local row = (2^z)-y-1

			-- retrieve a cursor
			local stmt = "INSERT INTO tiles(zoom_level, tile_column, tile_row, tile_data) VALUES("..tostring(z)..","..tostring(x)..","..tostring(row)..",x'"..MOAIDataBuffer.hexEncode(buffer:getString()).."')"
			local start3 = MOAISim.getDeviceTime()
			if not self.trans or self.trans == 0 then
				local start = MOAISim.getDeviceTime()
				local count, err = self.conn:execute("BEGIN TRANSACTION")
				local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
				print("sqlite:saveTile:Begin Transaction returned "..tostring(count).." and "..tostring(err).." took "..elapsed.." msec")
				serviceWithDelay( "commit", 2*1000, function()
							if self.trans > 0 then
								local start = MOAISim.getDeviceTime()
								local count, err = self.conn:execute("COMMIT")
								local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
								print("sqlite:saveTile:Commit("..tostring(self.trans)..") took "..elapsed.." msec")
	--toast.new("Commit("..tostring(trans)..") in "..tostring(elapsed).." msec", 2000)
								self.trans = 0
							else
								print("sqlite:saveTile:Huh?  Trans is "..tostring(self.trans).."?")
							end
						end)
			end
			local count, err = 	self.conn:execute(stmt)
			self.trans = (self.trans and self.trans or 0) + 1
			local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
			local elapsed1 = string.format("%.2f", (start2 - start) * 1000)
			local elapsed2 = string.format("%.2f", (start3 - start2) * 1000)
			local elapsed3 = string.format("%.2f", (MOAISim.getDeviceTime() - start3) * 1000)
			if count == 1 then
--local info = debug.getinfo( 2, "Sl" )
--local where = info.source..':'..info.currentline
--if where:sub(1,1) == '@' then where = where:sub(2) end
--print(where..">sqlite:saveTile:INSERT="..tostring(count)..","..tostring(err).." "..tostring(n).." for "..tostring(z).."/"..tostring(x).."/"..tostring(y).." took "..tostring(elapsed1).."+"..tostring(elapsed2).."+"..tostring(elapsed3).."="..tostring(elapsed).." msec")
--print(where.."Statement:"..stmt)
				if self.contents then
					local zc = self.contents and self.contents[z] or nil
					if not zc then
						self.contents[z] = {count=1,min_y=y,max_y=y,min_x=x,max_x=x}
					else
						zc.count = zc.count + 1
						if y < zc.min_y then zc.min_y = y end
						if y > zc.max_y then zc.max_y = y end
						if x < zc.min_x then zc.min_x = x end
						if x > zc.max_x then zc.max_x = x end
					end
				end
			else
				if not count then
					count = self:getBlob(n,x,y,z) ~= nil
				end
				if not count then
local info = debug.getinfo( 2, "Sl" )
local where = info.source..':'..info.currentline
if where:sub(1,1) == '@' then where = where:sub(2) end
print(where..">sqlite:saveTile:INSERT="..tostring(count)..","..tostring(err).." "..tostring(n).." for "..tostring(z).."/"..tostring(x).."/"..tostring(y).." took "..tostring(elapsed1).."+"..tostring(elapsed2).."+"..tostring(elapsed3).."="..tostring(elapsed).." msec")
print(where.."Statement:"..stmt)
				end
			end
	end
--	print("sqlite:close database")
--	closedb(env,conn)
	
end

function MBTile:saveTileFile(n,x,y,z,dir,file)
	local buffer = MOAIDataBuffer.new()
	if buffer:load(dir.."/"..file) then
		self:saveTile(n,x,y,z,buffer)
	else print("sqlite:saveTileFile:Load("..dir.."/"..file..") Failed")
	end
end

function MBTile:getPixelCounts(zoom, imgsize, zmax, maxTime)

	local function pixelXY(row,column,zoom)

		local xp, yp, zp = column, 2^zoom-row-1, zoom
		while zp > zmax do
			xp = math.floor(xp / 2)
			yp = math.floor(yp / 2)
			zp = zp - 1
		end
		while zp < zmax do
			xp = xp * 2
			yp = yp * 2
			zp = zp + 1
		end
		if xp > imgsize then
			print ('x='..tostring(xp))
			xp = imgsize
		end
		if yp > imgsize then
			print ('y='..tostring(yp))
			yp = imgsize
		end
		return xp, yp, zp
	end

	print(string.format("getPixelCounts:maxDelay = %.1f msec", maxTime*1000))

	local counts, maxCount, totalCount = {}, 0, 0
	local start = MOAISim.getDeviceTime()
	local totalStart = MOAISim.getDeviceTime()
	local yieldCount = 0

	local cur, err = self.conn:execute(string.format("SELECT tile_column, tile_row from tiles where zoom_level=%d", zoom))
	local elapsed = (MOAISim.getDeviceTime()-start)
	print("getPixelCounts:Summary select took "..tostring(elapsed*1000).."msec")
	if elapsed > maxTime then
		yieldCount = yieldCount + 1
		coroutine.yield()
	end
	if cur then
		local start = MOAISim.getDeviceTime()
		local row = cur:fetch({},"a")
		while row do
			local xp, yp, zp = pixelXY(row.tile_row, row.tile_column, zoom)
			if zp ~= zmax then print(string.format("Huh?  zp=%d zmax=%d", zp, zmax)) end

			if not counts[yp] then counts[yp] = {} end
			if not counts[yp][xp] then counts[yp][xp] = 0 end
			counts[yp][xp] = counts[yp][xp] + 1
			if counts[yp][xp] > maxCount then maxCount = counts[yp][xp] end
			totalCount = totalCount + 1
			--print(string.format("sqlite:zoom:%i Row:%i Col:%i",
			--					zoom,
			--					row.tile_row, row.tile_column))

			local elapsed = (MOAISim.getDeviceTime()-start)
			if elapsed > maxTime then	-- 1/4 (25%) of frame rate
				--print("getContentImage:Summary Count yield after "..tostring(elapsed*1000).."msec")
				yieldCount = yieldCount + 1
				coroutine.yield()
				start = MOAISim.getDeviceTime()
			end
			row = cur:fetch({},"a")
		end
		cur:close() -- already closed because all the result set was consumed	
		local elapsed = (MOAISim.getDeviceTime()-start)
		if elapsed > maxTime then
			print("getPixelCounts:Summary Count took "..tostring(elapsed*1000).."msec")
			yieldCount = yieldCount + 1
			coroutine.yield()
		end
	else print("SELECT failed with "..tostring(err))
	end
	local elapsed = (MOAISim.getDeviceTime()-totalStart)
	print(string.format("getPixelCounts:Took %.2fmsec including %d yields", elapsed*1000, yieldCount));
	return counts, maxCount, totalCount
end
	
return MBTile
