-- select zoom_level, tile_column, tile_row, tile_date, datetime(tile_date,'unixepoch'), datetime(tile_expires,'unixepoch') from tiles where zoom_level = 8;

local function prequire(m) 
  local ok, err = pcall(require, m) 
  if not ok then return nil, err end
  return err
end

-- If we don't have sqlite3, then we're running a generic moai.  Fall back to mbtilesql which uses luasql
local sqlite3, err = prequire("sqlite3")
if not sqlite3 and err then
	print('sqlite3 not found, some MBTiles features not available')
	return require("mbtilesql")
end

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
	for row in self.conn:nrows("select value from metadata where name='"..key.."'") do
		return row.value
	end
	return nil
end

function MBTile:addMetaValue(key, value)
	local stmt = string.format("INSERT INTO metadata(name, value) VALUES('%s','%s')", key, value)
	if self.conn:execute(stmt) == sqlite3.OK then
		print("Add MetaValue("..key..") to("..value..") updated "..tostring(self.conn:changes()))
		if self.conn:changes() == 1 then
			return true
		else return false
		end
	else print("sqlite:Insert "..key.." metadata in "..self.db.." err:"..tostring(self.conn:errmsg()))
	end
	return false
end

function MBTile:setMetaValue(key, value)
	if self.conn:execute("update metadata set value='"..value.."' where name='"..key.."'") == sqlite3.OK then
		print("Update MetaValue("..key..") to("..value..") updated "..tostring(self.conn:changes()))
		if self.conn:changes() == 1 then
			return true
		else return false
		end
	else print("sqlite:Update "..key.." metadata in "..self.db.." err:"..tostring(self.conn:errmsg()))
	end
	return false
end

function MBTile:recallGateways()
	local columns = {}
	for row in self.conn:nrows("pragma table_info(gateways)") do
		columns[row.name] = row
	end
	if #columns == 0 then
		if self.conn:execute("CREATE TABLE IF NOT EXISTS gateways (URI TEXT PRIMARY KEY, API INTEGER, response REAL, good INTEGER)") ~= sqlite3.OK then
			print(string.format("DB(%s) Failed to add gateways table, error:%s", self.name, tostring(self.conn:errmsg())))
			return nil
		else print(string.format("DB(%s) added gateways table, updated %d", self.name, self.conn:changes()))
		end
	end

	local gateways = {}
	for row in self.conn:nrows("SELECT * from gateways;") do
		gateways[row.URI] = row
	end
	return gateways
end

function MBTile:getGateway(URI)
	for row in self.conn:nrows("select * from gateways where URI='"..URI.."'") do
		print(printableTable(URI,row))
		return row
	end
	return nil
end

function MBTile:dropGateway(URI)
	local stmt = string.format("DELETE FROM gateways WHERE URI='%s'", URI)
	if self.conn:execute(stmt) == sqlite3.OK then
--		print("Drop gateway("..URI..") updated "..tostring(self.conn:changes()))
		if self.conn:changes() == 1 then
			return true
		else return false
		end
	else print("sqlite:Drop gateway "..URI.." in "..self.db.." err:"..tostring(self.conn:errmsg()))
	end
	return false
end

function MBTile:saveGateway(URI, API, response, good)
	local stmt = string.format("INSERT INTO gateways(URI, API, response, good) VALUES('%s',%d,%f,%d)"..
								" ON CONFLICT(URI) DO UPDATE SET API=excluded.API, response=excluded.response, good=gateways.good+excluded.good;",
								URI, API and 1 or 0, response, good or 0)
	if self.conn:execute(stmt) == sqlite3.OK then
--		print("Save gateway("..URI..") updated "..tostring(self.conn:changes()))
		if self.conn:changes() == 1 then
			return true
		else return false
		end
	else print("sqlite:Insert gateway "..URI.." in "..self.db.." err:"..tostring(self.conn:errmsg()))
	end
	return false
end

function MBTile:addDateColumns()
-- pragma table_info(tiles)
-- select type from sqlite_master where name = "tiles"
	local tilesType = nil
	for row in self.conn:nrows("select type from sqlite_master where name = 'tiles'") do
		tilesType = row.type
	end
	if tilesType ~= "table" then
		print(string.format("DB(%s) tiles is '%s', not a 'table', Not doing Dates", self.name, tilesType))
		return false
	end
	local columns = {}
	for row in self.conn:nrows("pragma table_info(tiles)") do
		columns[row.name] = row
	end
	print(printableTable("tilesColumsn", columns))
	print(string.format("zoom_level(%s) tile_data(%s)", tostring(columns.zoom_level.type), tostring(columns.tile_data.type)))
	if columns.tile_expires and columns.tile_date then
		if columns.tile_expires.type == "integer" and columns.tile_date.type == "integer" then
			print(string.format("DB(%s) Supports expiration!", self.name))
			self.supportsExpiration = true
			return true
		end
		print(string.format("DB(%s) has invalid tile_expires(%s) and tile_date(%s), should be 'integer'", self.name, (columns.tile_expires.type), tostring(columns.tile_date.type)))
		return false
	end
	if self.conn:execute("ALTER TABLE tiles ADD COLUMN tile_date integer DEFAULT 0") ~= sqlite3.OK then
		print(string.format("DB(%s) Failed to add tile_date column, error:%s", self.name, tostring(self.conn:errmsg())))
		return false
	else print(string.format("DB(%s) added tile_date column, updated %d", self.name, self.conn:changes()))
	end
	if self.conn:execute("ALTER TABLE tiles ADD COLUMN tile_expires integer DEFAULT 0") ~= sqlite3.OK then
		print(string.format("DB(%s) Failed to add tile_expires column, error:%s", self.name, tostring(self.conn:errmsg())))
		return false
	else print(string.format("DB(%s) added tile_expires column, updated %d", self.name, self.conn:changes()))
	end
	self.supportsExpiration = true
	return true
end

function MBTile:countContents()
	local start = MOAISim.getDeviceTime()
	self.contents = {}
	for row in self.conn:nrows("SELECT zoom_level, count(*) as count, min(tile_column) as min_col, max(tile_column) as max_col, min(tile_row) as min_row, max(tile_row) as max_row from tiles group by zoom_level order by zoom_level") do
		self.contents[row.zoom_level] = {count=row.count,
									max_y=(2^row.zoom_level)-row.min_row-1,
									min_y=(2^row.zoom_level)-row.max_row-1,
									min_x=row.min_col,
									max_x=row.max_col }
		--[[print(string.format("sqlite:zoom:%i Count:%i Rows:%i-%i Cols:%i-%i",
							row.zoom_level, row.count,
							row.min_row, row.max_row,
							row.min_col, row.max_col))]]
	end
	local elapsed = (MOAISim.getDeviceTime()-start)*1000
	print("Count took "..tostring(elapsed).."msec")
	self.contents.name = self.name
	self.contents.elapsed = elapsed
	return true
end

function MBTile:_init(db)
	local err, errmsg
	self.db = db
	self.conn, err, errmsg = sqlite3.open(db)
	if not self.conn then
		return nil, errmsg
	end

	print("sqlite:Got database connection to "..db)

	self.name = self:getMetaValue("name")
	if not self.name then
		self.conn:close()
		self.conn = nil
		return nil, "Non-MBTiles Database"
	end
	
	do
		local fullPath = MOAIFileSystem.getAbsoluteFilePath(db)
		--local start, finish = fullPath:find('[%w%s!-={-|]+[_%.].+')
		local start, finish = fullPath:find("/[^/]*$")
		local fileName = fullPath:sub(start+1)
		print(string.format("dbUpgrade:FullPath:%s has name:%s", fullPath, fileName))
		local orgPath = MOAIFileSystem.getAbsoluteFilePath(fileName)
		if orgPath ~= fullPath then
			local actualPath = orgPath
			local distConn, err, errmsg = sqlite3.open(actualPath,sqlite3.OPEN_READONLY)
			if not distConn then
				print(string.format("dbUpgrade:sqlite3.open(%s) failed with %s or %s", actualPath, tostring(err), tostring(errmsg)))
				local tempDir = MOAIEnvironment.externalCacheDirectory or MOAIEnvironment.cacheDirectory or MOAIEnvironment.documentDirectory or "temp"
				actualPath = tempDir.."/"..fileName
				MOAIFileSystem.copy(orgPath, actualPath)
				print(string.format("Copied %s to %s temporarily", orgPath, actualPath))
				distConn, err, errmsg = sqlite3.open(actualPath,sqlite3.OPEN_READONLY)
			end
			if distConn then
				print(string.format("dbUpgrade:Successfully opened %s", actualPath))
				for row in distConn:nrows("SELECT name, value from metadata;") do
					local hadValue = self:getMetaValue(row.name)
					print(string.format("dbUpgrade:metadata(%s) %s have %s", tostring(row.name), tostring(row.value), tostring(hadValue)))
					if hadValue ~= row.value then
						if hadValue then
							if self:setMetaValue(row.name, row.value) then
								print(string.format("dbUpgrade:metadata(%s) %s replaced %s", tostring(row.name), tostring(row.value), tostring(hadValue)))
							else toast.new("Failed To Update "..row.name.." in "..db)
							end
						else
							if self:addMetaValue(row.name, row.value) then
								print(string.format("dbUpgrade:metadata(%s) %s added", tostring(row.name), tostring(row.value)))
							else toast.new("Failed To Insert "..row.name.." in "..db)
							end
						end
					end
				end
			else
				print(string.format("dbUpgrade:sqlite3.open(%s) failed with %s or %s", actualPath, tostring(err), tostring(errmsg)))
			end
			if actualPath ~= orgPath then
				MOAIFileSystem.deleteFile(actualPath)	-- Remove the temp copy
			end
		else print(string.format("dbUpgrade:Not upgrading single DB %s", tostring(fullPath)))
		end
	end

	self.IPFSBase = self:getMetaValue("IPFSBase")
	self.IPFSGateways = self:getMetaValue("IPFSGateways")
	self.IPFSHomeGateway = self:getMetaValue("IPFSHomeGateway")
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

	self:addDateColumns()
	
	self:countContents()
	
	return self
end

function MBTile:deleteAllTiles()
	if self.conn:execute("DELETE FROM tiles;") ~= sqlite3.OK then
		print(string.format("DB(%s) Failed to delete tiles, error:%s", self.name, tostring(self.conn:errmsg())))
		return nil, tostring(self.conn:errmsg())
	end
	local deleted = self.conn:changes()
	print(string.format("DB(%s) deleted %d tiles", self.name, deleted))
	if self.conn:execute("VACUUM") ~= sqlite3.OK then
		print(string.format("DB(%s) Failed to VACUUM, error:%s", self.name, tostring(self.conn:errmsg())))
	end
	self:countContents()
	
	return deleted
end

function MBTile:checkExpiration(x,y,z,Date,Expires)

	if not self.supportsExpiration or not Date or not Expires then return nil end
	local now = os.time()
	if Expires < now then
	--[[
		local sDate, sExpires
		if Date and Date ~= 0 then sDate = os.date("!%Y-%m-%d %H:%M:%S", Date) else sDate = tostring(Date) end
		if Expires and Expires ~= 0 then sExpires = os.date("!%Y-%m-%d %H:%M:%S", Expires) else sExpires = tostring(Expires) end
		if Expires ~= 0 then
			print(string.format("DB(%s) %d/%d/%d %s is Expired %s by %d seconds (%.0f hours or %.1f days) Now:%s", self.name, z, x, y, sDate, sExpires, now-Expires, (now-Expires)/3600, (now-Expires)/3600/24, os.date("!%Y-%m-%d %H:%M:%S", now)))
		else print(string.format("DB(%s) %d/%d/%d %s is pre-Expired(0)", self.name, z, x, y, sDate))
		end
		]]
		return Date
--	else
--		local sDate
--		if Date and Date ~= 0 then sDate = os.date("!%Y-%m-%d %H:%M:%S", Date) else sDate = tostring(Date) end
--		local sExpired = os.date("!%Y-%m-%d %H:%M:%S", Expires)
--		print(string.format("DB(%s) %d/%d/%d %s is NOT Expired(%s)", self.name, z, x, y, sDate, sExpired))
	end
	return nil
end

function MBTile:getBlob(n,x,y,z)
	if self.conn then
		local row = (2^z)-y-1
		local zc = self.contents and self.contents[z] or nil

		if not zc
		or (y>=zc.min_y and y<=zc.max_y
			and x>=zc.min_x and x<=zc.max_x) then	-- Is it at least in range of the contents?
			-- retrieve a cursor
			if self.supportsExpiration then
				for blob, Date, Expires in self.conn:urows("SELECT tile_data, tile_date, tile_expires from tiles where zoom_level="..tostring(z).." and tile_row="..tostring(row).." and tile_column="..tostring(x)) do
					--print("sqlite:Got "..tostring(#blob).." bytes for "..tostring(z).."/"..tostring(x).."/"..tostring(y))
					return blob, Date, Expires
				end
			else 
				for blob in self.conn:urows("SELECT tile_data from tiles where zoom_level="..tostring(z).." and tile_row="..tostring(row).." and tile_column="..tostring(x)) do
					--print("sqlite:Got "..tostring(#blob).." bytes for "..tostring(z).."/"..tostring(x).."/"..tostring(y))
					return blob
				end
			end
		end
	end
	--print("sqlite:no row for "..tostring(z).."/"..tostring(x).."/"..tostring(y))
	return nil
end

function MBTile:checkTile(n,x,y,z)
	local start = MOAISim.getDeviceTime()

	local file = string.format('%s/%i/%i/%i.png', self.name, z, x, y)
	if not self.tileCache then
		self.tileCache, self.expireCache = {}, {}
		setmetatable(self.tileCache, { __mode = 'v' })	-- k means weak key, v means weak value, kv means weak both
		setmetatable(self.expireCache, { __mode = 'k' })	-- k means weak key, v means weak value, kv means weak both
	end
	local texture = self.tileCache[file]	-- Make it a strong reference
	if texture then
		local expire = self.expireCache[texture]
		local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
		--print("sqlite:checkTile "..tostring(n).." for "..tostring(z).."/"..tostring(x).."/"..tostring(y).." CACHE took "..tostring(elapsed).." msec")
print(string.format("Using cached(%s) or %s %s", file, tostring(texture), tostring(expire)))
		return true, expire
	end
	local blob, Date, Expires = self:getBlob(n,x,y,z)
	local LastDate = self:checkExpiration(x,y,z,Date,Expires)
	--print(string.format("checkTile: returning %s for %i/%i/%i", tostring(LastDate), z, x, y))
	return blob ~= nil, LastDate
end

--[[
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
]]

function MBTile:getTileTexture(n,x,y,z)
	local start = MOAISim.getDeviceTime()

	local file = string.format('%s/%i/%i/%i.png', self.name, z, x, y)
	if not self.tileCache then
		self.tileCache, self.expireCache = {}, {}
		setmetatable(self.tileCache, { __mode = 'v' })	-- k means weak key, v means weak value, kv means weak both
		setmetatable(self.expireCache, { __mode = 'k' })	-- k means weak key, v means weak value, kv means weak both
	end
	local texture = self.tileCache[file]	-- Make it a strong reference
	if texture then
		local expire = self.expireCache[texture]
--local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
--local info = debug.getinfo( 2, "Sl" )
--local where = info.source..':'..info.currentline
--if where:sub(1,1) == '@' then where = where:sub(2) end
--print("sqlite:getTile "..tostring(n).." for "..tostring(z).."/"..tostring(x).."/"..tostring(y).." CACHE took "..tostring(elapsed).." msec".." from "..tostring(where))
--print(string.format("Returning cached(%s) or %s %s", file, tostring(texture), tostring(expire)))
		return texture, expire
	end

	local blob, Date, Expires = self:getBlob(n,x,y,z)
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

		local LastDate = self:checkExpiration(x,y,z,Date,Expires)
		self.tileCache[file] = image
		self.expireCache[image] = LastDate
--print(string.format("Set cached(%s) or %s %s", file, tostring(image), tostring(LastDate)))
		return image, LastDate
	--else
		--print("Tile "..file.." not found in "..self.db)
	end
	return nil
end

function MBTile:saveTile(n,x,y,z,buffer,Date,Expires)

	local start = MOAISim.getDeviceTime()

	local blob = nil

	if self.conn then
--		print("sqlite:saveTile "..tostring(n).." for "..tostring(z).."/"..tostring(x).."/"..tostring(y).." from buffer")

			local start2 = MOAISim.getDeviceTime()

			local row = (2^z)-y-1

			-- retrieve a cursor
			-- Note: This could use REPLACE https://www.sqlitetutorial.net/sqlite-replace-statement/
			-- But then we wouldn't have any indication of double-fetching a given tile
			-- But we might want to use that for expiration updating?
			-- Or UPSERT if >3.24.0 https://www.sqlite.org/lang_UPSERT.html https://stackoverflow.com/questions/15277373/sqlite-upsert-update-or-insert/15277374
			local stmt

			if self.supportsExpiration then
				Date = tonumber(Date) or os.time()
				if type(Expires) ~= 'number' then
					local info = debug.getinfo( 2, "Sl" )
					local where = info.source..':'..info.currentline
					if where:sub(1,1) == '@' then where = where:sub(2) end
					if Expires then print(string.format("DB(%s):Ignoring Expires(%s)=%s from %s", self.name, type(Expires), tostring(Expires), where)) end
					Expires = os.time() + 7*24*60*60	-- Default expiration is 1 week
				end
				--print(string.format("DB(%s) Updating %i/%i/%i Date:%s Expires:%s", self.name, z, x, y, os.date("!%Y-%m-%d %H:%M:%S",Date), os.date("!%Y-%m-%d %H:%M:%S",Expires)))
				stmt = string.format("REPLACE INTO tiles(zoom_level, tile_column, tile_row, tile_date, tile_expires, tile_data) VALUES(%d,%d,%d,%d,%d,x'%s')",
										z, x, row, Date, Expires, MOAIDataBuffer.hexEncode(buffer:getString()))
			else
				stmt = string.format("INSERT INTO tiles(zoom_level, tile_column, tile_row, tile_data) VALUES(%d,%d,%d,x'%s')", z, x, row, MOAIDataBuffer.hexEncode(buffer:getString()))
			end

			local start3 = MOAISim.getDeviceTime()
			if not self.trans or self.trans == 0 then
				local start = MOAISim.getDeviceTime()
				local status = self.conn:execute("BEGIN TRANSACTION")
				local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
				print("sqlite:saveTile:Begin Transaction returned "..tostring(status).." and took "..elapsed.." msec")
				serviceWithDelay( "commit", 2*1000, function()
							if self.trans and self.trans > 0 then
								local start = MOAISim.getDeviceTime()
								local status = self.conn:execute("COMMIT")
								local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
								print("sqlite:saveTile:Commit("..tostring(self.trans)..") took "..elapsed.." msec")
	--toast.new("Commit("..tostring(trans)..") in "..tostring(elapsed).." msec", 2000)
								self.trans = 0
							else
								print("sqlite:saveTile:Huh?  Trans is "..tostring(self.trans).."?")
							end
						end)
			end

			local file = string.format('%s/%i/%i/%i.png', self.name, z, x, y)
			if self.conn:execute(stmt) == sqlite3.OK then
			

	-- If we just got this, and it's cached, remove the expiration
	local file = string.format('%s/%i/%i/%i.png', self.name, z, x, y)
	if self.tileCache then
		local cache = self.tileCache[file]	-- Make strong reference
		if cache then
print(string.format("Pruning cached(%s) or %s", file, printableTable("tileCache", self.tileCache[file])))
		-- self.tileCache[file] = { self.tileCache[file][1] }
			self.expireCache[cache] = nil
		end
	end

				self.trans = (self.trans and self.trans or 0) + 1
				local elapsed = string.format("%.2f", (MOAISim.getDeviceTime() - start) * 1000)
				local elapsed1 = string.format("%.2f", (start2 - start) * 1000)
				local elapsed2 = string.format("%.2f", (start3 - start2) * 1000)
				local elapsed3 = string.format("%.2f", (MOAISim.getDeviceTime() - start3) * 1000)
				if self.conn:changes() == 1 then
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
					--print(string.format("sqlite:Inserted Tile %s in %s", file, self.db))
					
--[[
					if self.supportsExpiration then
						
						Date = tonumber(Date) or os.time()
						if Expires and type(Expires) ~= 'number' then
							local info = debug.getinfo( 2, "Sl" )
							local where = info.source..':'..info.currentline
							if where:sub(1,1) == '@' then where = where:sub(2) end
							print(string.format("DB(%s):Ignoring Expires(%s)=%s from %s", self.name, type(Expires), tostring(Expires), where))
							Expires = nil
						end
						
						local update
						if Expires then 
							update = string.format("UPDATE tiles SET tile_date=%d, tile_expires=%d WHERE zoom_level=%d and tile_row=%d and tile_column=%d", Date, Expires, z, row, x)
						else update = string.format("UPDATE tiles SET tile_date=%d tile_WHERE zoom_level=%d and tile_row=%d and tile_column=%d", Date, z, row, x)
						end
						if self.conn:execute(update) == sqlite3.OK then
							if self.conn:changes() ~= 1 then
								print(string.format("DB(%s) update Date(%s)/Expires(%s) FAILED, changes=%s", self.name, tostring(Date), tostring(Expires), tostring(self.conn:changes())))
							else print(string.format("DB(%s) updated Date(%s)/Expires(%s), changes=%s", self.name, tostring(Date), tostring(Expires), tostring(self.conn:changes())))
							end
						else
							print(string.format("DB(%s) update Date/Expires failed, error:%s\n%s", self.name, tostring(self.conn:errmsg()), update))
						end
					end
]]
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
			else
				print(string.format("sqlite:Insert Tile %s in %s err: %s", file, self.db, tostring(self.conn:errmsg())))
			end
	end

end

function MBTile:saveTileFile(n,x,y,z,dir,file,Date,Expires)
	local buffer = MOAIDataBuffer.new()
	if buffer:load(dir.."/"..file) then
		self:saveTile(n,x,y,z,buffer,Date,Expires)
	else print("sqlite:saveTileFile:Load("..dir.."/"..file..") Failed")
	end
end

function MBTile:getPixelCounts2(xIn, yIn, zoom, imgsize, zmax, maxTime)
	maxTime = maxTime or 0
	print(string.format("getPixelCounts2:maxDelay = %.1f msec", maxTime*1000))

	local zoomdiff = zmax - zoom
	local zd2 = 2^zoomdiff
	print(string.format("zoom:%d zmax:%d gives diff:%d zd2:%f", zoom, zmax, zoomdiff, zd2))

	print(string.format("getPixelCounts2:xIn=%d yIn=%d zoom=%d", xIn, yIn, zoom))

	local zoom2 = 2^zoom
	xIn = math.floor(xIn/256)*256
	yIn = math.floor(yIn/256)*256

	print(string.format("getPixelCounts2:NOW:xIn=%d yIn=%d zoom2=%d", xIn, yIn, zoom2))

	local function pixelXY(row,column,zoom)

		local xp, yp, zp = column, zoom2-row-1, zoom
		xp = math.floor((xp-xIn)*zd2)
		yp = math.floor((yp-yIn)*zd2)
		zp = zp+zoomdiff
		if zp ~= zmax then
			print("z="..tostring(zp).." should be "..zoom)
		end
		if xp > imgsize or xp < 0 then
			print ('x='..tostring(xp))
			xp = imgsize
		end
		if yp > imgsize or yp < 0 then
			print ('y='..tostring(yp))
			yp = imgsize
		end
		return xp, yp, zp
	end

	local counts, maxCount, totalCount = {}, 0, 0
	local start = MOAISim.getDeviceTime()
	local first = true
	local yieldCount = 0
	local totalStart = start
	local colMin, colMax = xIn, xIn+256-1
	local rowMax, rowMin = zoom2-(yIn)-1, zoom2-(yIn+256-1)-1
	
	print(string.format("getPixelCounts2:row:%d-%d col:%d-%d", rowMin, rowMax, colMin, colMax))

 	for row in self.conn:nrows(string.format("SELECT tile_column, tile_row from tiles where zoom_level=%d and tile_row >= %d and tile_row <= %d and tile_column >= %d and tile_column <= %d", zoom, rowMin, rowMax, colMin, colMax)) do
-- 	for row in self.conn:nrows(string.format("SELECT tile_column, tile_row from tiles where zoom_level=%d", zoom, rowMin, rowMax, colMin, colMax)) do
		if first then	-- First row returned
			local elapsed = (MOAISim.getDeviceTime()-start)
			print("getPixelCounts:Summary select took "..tostring(elapsed*1000).."msec")
			if maxTime > 0 and elapsed > maxTime then
				yieldCount = yieldCount + 1
				coroutine.yield()
			end
			start = MOAISim.getDeviceTime()
			first = false
		end

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
		if maxTime > 0 and elapsed > maxTime then
			--print("getPixelCounts2:Summary Count took "..tostring(elapsed*1000).."msec")
			yieldCount = yieldCount + 1
			coroutine.yield()
			start = MOAISim.getDeviceTime()	-- Reset the start time
		end
	end
	local elapsed = (MOAISim.getDeviceTime()-start)
	if maxTime > 0 and elapsed > maxTime then
		print("getPixelCounts2:Summary Count took "..tostring(elapsed*1000).."msec")
		yieldCount = yieldCount + 1
		coroutine.yield()
	end
	local elapsed = (MOAISim.getDeviceTime()-totalStart)
	print(string.format("getPixelCounts2:Took %.2fmsec including %d yields", elapsed*1000, yieldCount));
	return counts, maxCount, totalCount
end

function MBTile:getPixelCounts(zoom, imgsize, zmax, maxTime)
	maxTime = maxTime or 0

	local zoomdiff = zmax - zoom
	local zd2 = 2^zoomdiff
	print(string.format("zoom:%d zmax:%d gives diff:%d zd2:%d", zoom, zmax, zoomdiff, zd2))
	local zoom2 = 2^zoom

	local function pixelXY(row,column,zoom)

		local xp, yp, zp = column, zoom2-row-1, zoom
		xp = math.floor(xp*zd2)
		yp = math.floor(yp*zd2)
		zp = zp+zoomdiff
		if zp ~= zmax then
			print("z="..tostring(zp).." should be "..zoom)
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
	local first = true
	local yieldCount = 0
	local totalStart = start

	for row in self.conn:nrows(string.format("SELECT tile_column, tile_row from tiles where zoom_level=%d", zoom)) do
		if first then	-- First row returned
			local elapsed = (MOAISim.getDeviceTime()-start)
			print("getPixelCounts:Summary select took "..tostring(elapsed*1000).."msec")
			if maxTime > 0 and elapsed > maxTime then
				yieldCount = yieldCount + 1
				coroutine.yield()
			end
			start = MOAISim.getDeviceTime()
			first = false
		end

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
		if maxTime > 0 and elapsed > maxTime then
			--print("getPixelCounts:Summary Count took "..tostring(elapsed*1000).."msec")
			yieldCount = yieldCount + 1
			coroutine.yield()
			start = MOAISim.getDeviceTime()	-- Reset the start time
		end
	end
	local elapsed = (MOAISim.getDeviceTime()-start)
	if maxTime > 0 and elapsed > maxTime then
		print("getPixelCounts:Summary Count took "..tostring(elapsed*1000).."msec")
		yieldCount = yieldCount + 1
		coroutine.yield()
	end
	local elapsed = (MOAISim.getDeviceTime()-totalStart)
	print(string.format("getPixelCounts:Took %.2fmsec including %d yields", elapsed*1000, yieldCount));
	return counts, maxCount, totalCount
end

return MBTile
