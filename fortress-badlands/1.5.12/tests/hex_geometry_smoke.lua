-- Board geometry and fortress visibility regression for the premium hex floor.
package.path='./?.lua;'..package.path
local drawn={}
local imageDraws={}
local width,height=390,760
love={graphics={},timer={getTime=function()return .1 end},
 math={random=function(a,b)
  if a and b then return math.random(a,b) elseif a then return math.random(a) end
  return math.random()
 end},
 filesystem={createDirectory=function()return true end,getInfo=function()return nil end,
  read=function()return nil end,write=function()return true end}}
local g=love.graphics
for _,name in ipairs({'setColor','setFont','polygon','setLineWidth','circle',
 'line','setStencilTest'}) do g[name]=function()end end
g.draw=function(img) if img and img.path then imageDraws[#imageDraws+1]=img.path end end
g.printf=function()end
g.rectangle=function(mode,x,y,w,h)
 if mode=='fill' then drawn[#drawn+1]={x=x,y=y,w=w,h=h} end
end
g.newFont=function(size)return {size=size} end
g.getDimensions=function()return width,height end
g.newImage=function(path)
 local w,h=path=='art/board.png' and 984 or 144,path=='art/board.png' and 1383 or 144
 return {path=path,getDimensions=function()return w,h end,
  getWidth=function()return w end,setFilter=function()end}
end
g.stencil=function(fn)fn()end
package.preload.zompa=function()return {
 mode=function()return 'solo',false end,
 audio=function()return {update=function()end}end,
 saveSession=function()return true end,loadSession=function()return nil end,
 clearSession=function()return true end
}end
local rules=require('rules')
dofile('main.lua')
love.load()
love.update(4.4) -- Inspect the board after the launch animation.
local function get(fn,name)
 for i=1,120 do
  local n,v=debug.getupvalue(fn,i)
  if n==name then return v end
  if not n then break end
 end
 error('missing upvalue '..name)
end
local layout=get(love.draw,'layout')
local state=get(love.draw,'state')
local board=get(love.draw,'drawBoard')
local center=get(board,'center')
local touch=get(love.touchpressed,'touch')
local onTap=get(touch,'onTap')
local hit=get(onTap,'xyToCell')
local function near(a,b)
 assert(math.abs(a-b)<.0001,('not aligned: %.4f vs %.4f'):format(a,b))
end
local sqrt3=math.sqrt(3)
near(layout.hexStepX,sqrt3*layout.hexR)
near(layout.hexStepY,1.5*layout.hexR)
local x1,y1=center(4,2)
local x2,y2=center(4,3)
near(x2-x1,sqrt3*layout.hexR)
near(y1,y2)
local xa,ya=center(5,2)
near(xa-x1,sqrt3*.5*layout.hexR)
near(ya-y1,1.5*layout.hexR)
local widths={3,4,5,6,7,6,7,6,5,4,3}
local total=0
for row=0,10 do
 assert(rules.rowWidths[row+1]==widths[row+1])
 for col=0,widths[row+1]-1 do
  local x,y=center(row,col)
  local p=hit(x,y)
  assert(p and p.r==row and p.c==col,
    ('hex center tap mismatch at %d,%d'):format(row,col))
  total=total+1
 end
end
assert(total==56)
local invalid=hit(-100,-100)
assert(invalid==nil)
-- Both separate two-tower Fortress assets are displayed, then correctly
-- disappear only after their game HP has reached zero.
local function countFortresses()
 imageDraws={}
 love.draw()
 local n=0
 for _,path in ipairs(imageDraws) do
  if path=='art/fortress-1.png' or path=='art/fortress-2.png' then n=n+1 end
 end
 return n
end
assert(state.forts[1].r==10 and state.forts[1].c==1)
assert(state.forts[2].r==0 and state.forts[2].c==1)
local present=countFortresses()
assert(present==2,'two Fortress sprite assets missing on board')
state.forts[1].hp=0;state.forts[2].hp=0
local gone=countFortresses()
assert(gone==0,'destroyed Fortresses should disappear')
state.forts[1].hp=35;state.forts[2].hp=35
-- Validate responsive reflow preserves center-tile hit mapping on small screens.
for _,dims in ipairs({{280,480},{320,520},{390,700},{450,980}}) do
 width,height=dims[1],dims[2]
 love.resize(width,height)
 layout=get(love.draw,'layout')
 local topX,topY=center(0,1)
 local bottomX,bottomY=center(10,1)
 assert(topX>0 and topX<width and bottomX>0 and bottomX<width)
 assert(topY>layout.cardY+layout.cardH)
 assert(bottomY<height-54)
 local t,b=hit(topX,topY),hit(bottomX,bottomY)
 assert(t and t.r==0 and t.c==1)
 assert(b and b.r==10 and b.c==1)
 love.draw()
end
print('PASS: contiguous staggered hex floor, exact 56 tap targets, both two-tower fortresses, responsive viewport')
