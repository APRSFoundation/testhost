-- (c) Copyright 2010-2016 Geoff Leyland.
-- See LICENSE for license information

local shapefile = require("shapefile")
local projection_map = require("shapefile.projections")
local dbf = require("dbf")
local lfs = require("lfs")

local unpack

if not string.unpack then
  require("struct")
  unpack = function(file, length, format)
    return struct.unpack(format, file:read(length))
  end
else
  unpack = function(file, length, format)
    return file:read(length):unpack(format)
  end
end

------------------------------------------------------------------------------

local function files(dir_name, file_pattern, projection, callback)

  local function _files()
    for filename in lfs.dir(dir_name) do
      if filename:match("%.shp$") and
        (not file_pattern or filename:match(file_pattern)) then
        local name = filename:match("(.*)%.shp$")
        local sfi = io.open(dir_name.."/"..filename, "rb")
        local dfi = io.open(dir_name.."/"..name..".dbf", "rb")
        local ifi = io.open(dir_name.."/"..name..".shx", "rb")

        if projection then
          local projection_file = io.open(dir_name.."/"..name..".prj", "r")
          if projection_file then
            local l = projection_file:read("*all")
            local projection_string = l:match('^%w+%["?([^",]+)')
            local proj_projection = projection_map[projection_string]
            if proj_projection then
              projection:set_input(proj_projection)
            else
              error(("Unkown Projection: %s"):format(projection_string))
            end
          end
        end

        local sf, xmin, ymin, xmax, ymax = shapefile.use(sfi, projection)
        local df = dbf.use(dfi)

--[[        local function _shapes()
          while true do
            local s = sf:read()
            if not s then break end
            if s == "null shape" then
              df:skip()
            else
              local d = df:read()
              coroutine.yield(s, d)
            end
          end
        end
]]
        local function _shapes()
		  local c = 1
          while true do
		  
            local d = df:read()
			if not d then break end
			
			if type(callback) ~= 'function' or callback(d) then

local offset = sf.file:seek()
local iff = ifi:seek("set",(c-1)*8+100)
local ok, offset2, record_length_words = pcall(unpack, ifi, 8, ">ii")
if ok then
	print("Seeking "..tostring(c).." from offset "..tostring(offset).." shx says "..tostring(offset2*2).." "..tostring(record_length_words))
	sf.file:seek("set",offset2*2)
else print("Reading "..tostring(c).." from offset "..tostring(offset).." shx("..tostring(ifi)..") FAILED at offset "..tostring(iff).." with "..offset2)
end

            local s = sf:read()
            if not s then break end
            if s == "null shape" then
				print("Null shape!")
--              df:skip()
            else
              coroutine.yield(s, d)
            end
			end
			c = c + 1
          end
        end

        coroutine.yield(coroutine.wrap(_shapes), name, xmin, xmax, ymin, ymax)

        sf:close()
        df:close()
      end
    end
  end
  return coroutine.wrap(_files)
end


------------------------------------------------------------------------------

return { files=files }

------------------------------------------------------------------------------
