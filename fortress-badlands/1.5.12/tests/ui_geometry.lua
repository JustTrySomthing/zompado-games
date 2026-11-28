local M={}
function M.upvalue(fn,name)
  for i=1,math.huge do
    local key,value=debug.getupvalue(fn,i)
    if key==name then return value end
    if not key then error('Missing upvalue '..name) end
  end
end
function M.layout(love)
  return M.upvalue(love.draw,'layout')
end
function M.cell(love,r,c)
  return M.upvalue(M.upvalue(love.draw,'drawBoard'),'center')(r,c)
end
function M.button(love,name)
  return M.upvalue(M.upvalue(love.draw,'drawActionBar'),name)
end
function M.boxCenter(box)
  return box.x+box.w*.5,box.y+box.h*.5
end
return M
