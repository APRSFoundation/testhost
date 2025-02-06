--------------------------------------------------------------------------------
-- This is a class to draw a polygon mesh. <br>
-- Base Classes => DisplayObject, Resizable <br>
--------------------------------------------------------------------------------

-- import
local table                     = require "hp/lang/table"
local class                     = require "hp/lang/class"
local DisplayObject             = require "hp/display/DisplayObject"
local Resizable             = require "hp/display/Resizable"

-- class
local M                         = class(DisplayObject, Resizable)

--------------------------------------------------------------------------------
-- The constructor.
-- @param params (option)Parameter is set to Object.<br>
--------------------------------------------------------------------------------
function M:init(params)
    DisplayObject.init(self)

    params = params or {}
    params = type(params.points) == "table" and params or {points = params}
    
	local polygon = params.points
	local linecolor = params.linecolor or {0.45, 0.5, 1, 0.2}
	local linewidth = params.linewidth or 5
	local fillcolor = params.fillcolor or {0.45, 0.5, 1, 0.1}
	for c=1,4 do
		if type(linecolor[c]) ~= "number" then print("linecolor["..tostring(c).."]=("..tostring(linecolor[c])) end
	end
	linecolor[1] = linecolor[1]*linecolor[4]
	linecolor[2] = linecolor[2]*linecolor[4]
	linecolor[3] = linecolor[3]*linecolor[4]
	for c=1,4 do
		if type(fillcolor[c]) ~= "number" then print("fillcolor["..tostring(c).."]=("..tostring(fillcolor[c])) end
	end
	fillcolor[1] = fillcolor[1]*fillcolor[4]
	fillcolor[2] = fillcolor[2]*fillcolor[4]
	fillcolor[3] = fillcolor[3]*fillcolor[4]
	
	
--[[
	local region = MOAIRegion.new ()
	if type(polygon[1]) == 'table' then	-- table of tables is a multi-polygon
		region:reservePolygons ( #polygon )
		for r, p in ipairs(polygon) do
			region:reserveVertices ( 1, #p/2 )
			for i=1,#p,2 do
				region:setVertex(r,(i+1)/2,p[i], p[i+1])
			end
		end
	else	-- single level table is a single polygon
		region:reservePolygons ( 1 )
		region:reserveVertices ( 1, #polygon/2 )
		for i=1,#polygon,2 do
			local x,y = polygon[i], polygon[i+1]
			region:setVertex(1,(i+1)/2,x,y)
		end
	end
	region:bless ()

	local tess = MOAIVectorTesselator.new ()

	tess:pushCombo ()
		tess:pushRegion ( region )
	tess:finish ()

	local region2 = MOAIRegion.new ()
	tess:tesselate ( region2 )

	local vtxFormat = MOAIVertexFormatMgr.getFormat ( MOAIVertexFormatMgr.XYZC )

	local vtxBuffer = MOAIVertexBuffer.new ()
	local idxBuffer = MOAIIndexBuffer.new ()

	local totalElements = region2:getTriangles ( vtxBuffer, idxBuffer, 2, vtxFormat );
]]

tess = MOAIVectorTesselator.new ()

tess:setCircleResolution ( 32 )

tess:setFillStyle ( MOAIVectorTesselator.FILL_SOLID )	-- FILL_NONE, FILL_SOLID
tess:setFillColor ( unpack(fillcolor) )

tess:setStrokeStyle ( MOAIVectorTesselator.STROKE_NONE )	-- STROKE_NONE, STROKE_CENTER, STROKE_INTERIOR, STROKE_EXTERIOR
tess:setStrokeColor ( unpack(linecolor)  )
tess:setStrokeWidth ( linewidth )
tess:setJoinStyle ( MOAIVectorTesselator.JOIN_MITER )	-- JOIN_ROUND, JOIN_BEVEL, JOIN_MITER
tess:setCapStyle ( MOAIVectorTesselator.CAP_POINTY )	-- CAP_BUTT, CAP_POINTY, CAP_ROUND, CAP_SQUARE
tess:setMiterLimit ( linewidth )

--tess:pushTranslate ( 50, 100 )

--[[
tess:pushPoly ()
	tess:pushVertex ( 175, 175 )
	tess:pushVertex ( 175, -175 )
	tess:pushVertex ( -175, -175 )
	tess:pushVertex ( -175, 175 )
	tess:pushVertex ( 75, 175 )
	tess:pushVertex ( 75, -75 )
	tess:pushVertex ( -75, -75 )
	tess:pushVertex ( -75, 75 )
	tess:pushVertex ( -25, 75 )
	tess:pushVertex ( -25, -25 )
	tess:pushVertex ( 25, -25 )
	tess:pushVertex ( 25, 125 )
	tess:pushVertex ( -125, 125 )
	tess:pushVertex ( -125, -125 )
	tess:pushVertex ( 125, -125 )
	tess:pushVertex ( 125, 175 )
tess:finish ()
]]

	if type(polygon[1]) == 'table' then	-- table of tables is a multi-polygon
		for r, p in ipairs(polygon) do
			tess:pushPoly()
			for i=1,#p,2 do
				tess:pushVertex(p[i], p[i+1])
			end
			tess:finish()
		end
	else	-- single level table is a single polygon
		tess:pushPoly()
		for i=1,#polygon,2 do
			local x,y = polygon[i], polygon[i+1]
			tess:pushVertex(x,y)
		end
		tess:finish()
	end

local vtxFormat = MOAIVertexFormatMgr.getFormat ( MOAIVertexFormatMgr.XYZC )

local vtxBuffer = MOAIVertexBuffer.new ()
local idxBuffer = MOAIIndexBuffer.new ()

local totalElements = tess:tesselate ( vtxBuffer, idxBuffer, 2, vtxFormat );

	local mesh = MOAIMesh.new ()
	mesh:setVertexBuffer ( vtxBuffer, vtxFormat )
	mesh:setIndexBuffer ( idxBuffer )
	mesh:setPrimType ( MOAIMesh.GL_TRIANGLES )
	mesh:setShader ( MOAIShaderMgr.getShader ( MOAIShaderMgr.LINE_SHADER_3D ))
	mesh:setTotalElements ( totalElements )
	local bounds = { vtxBuffer:computeBounds ( vtxFormat ) }
	if bounds and bounds[1] then
--		print("Polygon:init:"..printableTable("Bounds",bounds))
		mesh:setBounds ( unpack(bounds) )
		self.bounds = bounds
--	else print("vtxBuffer:computeBounds() return nil for "..tostring(#polygon/2).." points resulting in "..tostring(totalElements).." Elements")
	end
	
    self:setDeck(mesh)
    self.deck = mesh

    self:copyParams(params)
end

----------------------------------------------------------------
-- Returns the bounds of the object.
-- @return xMin, yMin, zMin, xMax, yMax, zMax
----------------------------------------------------------------

function M:getBounds()
--	return self.deck:getBounds()
--	print("Polygon:getBounds:"..printableTable("Bounds",self.bounds))
	if self.bounds then
		return unpack(self.bounds)
	else return 0,0,0, 0,0,0
	end
end

--------------------------------------------------------------------------------
-- Set the height and width.<br>
-- @param width width
-- @param height height
--------------------------------------------------------------------------------
function M:setSize(width, height)
--[[
    width = width or self:getWidth()
    height = height or self:getHeight()
    
    local left, top = self:getPos()
    --self.deck:setRect(0, 0, width, height)
    --self.deck:setBounds(0, 0, width, height)
    --self:setPiv(width / 2, height / 2, 0)
		local info = debug.getinfo( 2, "Sl" )
		local where = info.source..':'..info.currentline
		if where:sub(1,1) == '@' then where = where:sub(2) end
	print(string.format("Polygon:setSize(%d%d):setPos(%d,%d) from %s", width, height, left, top, where))
--    self:setPos(left, top)
--	self:setPos(self.bounds[1],self.bounds[2])
]]
end

return M