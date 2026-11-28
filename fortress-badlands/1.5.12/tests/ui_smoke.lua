package.path='./?.lua;'..package.path
local saved={}
love={
  graphics={},
  timer={getTime=function() return os.clock() end},
  math={random=function(a,b) if a and b then return math.random(a,b) elseif a then return math.random(a) else return math.random() end end},
  filesystem={createDirectory=function()return true end,getInfo=function(k)return saved[k] and {type='file'} end,write=function(k,v)saved[k]=v;return true end,read=function(k)return saved[k] end,remove=function(k)saved[k]=nil;return true end},
}
local G=love.graphics
for _,fn in ipairs({'setColor','printf','setFont','polygon','setLineWidth','circle','rectangle','line'}) do G[fn]=function(...) end end
G.newFont=function(size) assert(type(size)=='number' and size>0);return {size=size} end
G.newImage=function(path)
  local w,h=path=='art/board.png' and 700 or 144, path=='art/board.png' and 984 or 144
  return {getDimensions=function()return w,h end, getWidth=function()return w end, setFilter=function()end}
end
G.draw=function(...) end
local width,height=390,700
G.getDimensions=function()return width,height end
-- Mock only SDK host integration. UI code still calls the actual Zompa API names.
package.preload.zompa=function()
  return {mode=function()return 'solo',false end,
    saveSession=function(x)saved.session=x;return true end,
    loadSession=function()return saved.session end,
    clearSession=function()saved.session=nil;return true end,
    audio=function()return {update=function()end}end}
end
dofile('main.lua')
love.load()
for _,dims in ipairs({{390,700},{320,520},{420,850},{280,480},{450,980}}) do
  width,height=dims[1],dims[2]
  love.resize(width,height)
  love.draw()
  love.update(0.05)
  love.draw()
end
-- Touch a real selectable soldier on the standard layout, then draw its info.
width,height=390,700; love.resize(width,height)
-- Tap approximate lower board (do not assume code-private pixel geometry).
love.touchpressed(1,width*.5,height*.68)
love.draw()

local screenW,screenH
love.system={getOS=function() return 'Web' end}
love.window={
  getDesktopDimensions=function() return screenW,screenH end,
  setMode=function(w,h) width,height=w,h;return true end,
}
local ui=require('tests.ui_geometry')
local previousBoardW=0
local stageOffset
G.push,G.pop=function() end,function() end
G.translate=function(x) stageOffset=x end
width,height=900,530
love.resize(width,height)
love.draw()
local wide=ui.layout(love)
assert(wide.w<height and stageOffset==wide.stageX and wide.stageX==math.floor((width-wide.w)/2))
screenW,screenH=900,530
love.load()
assert(width<height,'host should request a portrait canvas even on a landscape screen')
for _,display in ipairs({{280,550},{360,750},{412,890},{480,960}}) do
  screenW,screenH=display[1],display[2]
  love.load()
  love.draw()
  local layout=ui.layout(love)
  assert(width==screenW,'hosted canvas should use the phone width')
  assert(height<=screenH-112,'hosted canvas must leave room for Android chrome')
  assert(layout.boardW>previousBoardW,'board should grow on a wider phone')
  assert(layout.actionY+layout.actionH+3<=height-24,'action frame clips against the viewport')
  previousBoardW=layout.boardW
end
print('PASS: desktop resize and touch, hosted board grows with screen width, action frame remains visible')

local failedCanvases=0
G.newCanvas=function()
  failedCanvases=failedCanvases+1
  error('simulated unsupported canvas')
end
love.update(5)
love.resize(width,height)
love.draw();love.draw()
assert(failedCanvases==1,'unsupported canvas must not be allocated every frame')
love.resize(width,height)
love.draw();love.draw()
assert(failedCanvases==2,'canvas fallback must allow a retry on resize')
print('PASS: unsupported canvases fall back without retrying every frame')

local originalOpen=io.open
local viewportHeight=650
io.open=function(path,...)
  if path=='/zompado/viewport' then
    return {read=function() return '390:'..viewportHeight end,close=function() end}
  end
  return originalOpen(path,...)
end
for _,available in ipairs({650,590,690}) do
  viewportHeight=available
  love.update(1.01)
  love.resize(width,height)
  local fitted=ui.layout(love)
  assert(height==available and width==390)
  assert(fitted.actionY+fitted.actionH<=available-24)
end
io.open=originalOpen
print('PASS: host turn banner resizes the canvas and keeps its action frame visible')
