--------------------------------------------------------------------------------
-- This module object on which to draw the texture to be implemented. <br>
-- This module by itself can not be used.<br>
--------------------------------------------------------------------------------

local TextureManager = require("hp/manager/TextureManager")

local M = {}

--------------------------------------------------------------------------------
-- Set the Texture to self.deck. 
-- @param texture Path or texture.
--------------------------------------------------------------------------------
function M:setTexture(texture)
    assert(texture, "texture nil value!")
	
--print("TextureDrawable:setTexture("..tostring(texture)..")")
    
    if type(texture) == "string" then
        texture = TextureManager:request(texture)
    end
    if self.texture == texture then
--print("TextureDrawable:setTexture:texture already("..tostring(texture)..")")
        return
    end
    
    local left, top = self:getPos()
    local resize = self.texture == nil and self.setSize ~= nil
    self.texture = texture
--print("TextureDrawable:setTexture:setting deck("..tostring(texture)..")")
    self.deck:setTexture(texture)
    self:setPos(left, top)
    
    if resize then
        local w, h = texture:getSize()
        self:setSize(w, h)
    end
end

return M