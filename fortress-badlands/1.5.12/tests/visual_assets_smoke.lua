-- Regression: distinct red/blue portrait and token PNGs, live HUD typography.
package.path='./?.lua;'..package.path
local labels,drawn={},{}
local size={390,700}
local now=0
love={graphics={},timer={getTime=function()return now end},
 math={random=function(a,b) if a and b then return math.random(a,b) end
   if a then return math.random(a) end return math.random() end},
 filesystem={getInfo=function()return nil end,createDirectory=function()return true end,
  write=function()return true end,read=function()return nil end}}
local g=love.graphics
for _,k in ipairs({'setColor','setFont','polygon','setLineWidth','circle',
 'rectangle','line','setStencilTest'}) do g[k]=function()end end
local pulses={}
g.setColor=function(r,green,b,alpha)
 if r==1 and green==.26 and b==.18 then pulses[#pulses+1]=alpha end
end
g.printf=function(value)labels[#labels+1]=tostring(value) end
g.newFont=function(pt)return {size=pt}end
g.getDimensions=function()return size[1],size[2] end
g.stencil=function(fn)fn()end
local loaded={}
g.newQuad=function(x,y,w,h)return {getViewport=function()return x,y,w,h end}end
g.newImage=function(path)
 local f=assert(io.open(path,'rb'),'missing game art: '..path)
 local sig=f:read(8);f:close()
 assert(sig=='\137PNG\r\n\026\n','invalid PNG: '..path)
 loaded[path]=true
 local ww,hh=144,144
 if path:find('^portraits/') then ww,hh=240,240 end
 if path=='art/board.png' then ww,hh=984,1383 end
 if path=='art/weathered-flagstones.png' then ww,hh=1120,1760 end
 return {path=path,getDimensions=function()return ww,hh end,
  getWidth=function()return ww end,setFilter=function()end}
end
g.draw=function(sprite)drawn[#drawn+1]=sprite.path end
package.preload.zompa=function()return {
 mode=function()return 'solo',false end,audio=function()return {update=function()end}end,
 saveSession=function()return true end,loadSession=function()return 'v18|123|1|' end,
 clearSession=function()return true end
}end
local rules=require('rules')
dofile('main.lua');love.load()
local function slot(fn,name)
 for i=1,100 do
  local k,v=debug.getupvalue(fn,i)
  if k==name then return i,v end
  if not k then break end
 end
 error('missing upvalue '..name)
end
local _,drawCard=slot(love.draw,'drawCard')
local inspIndex=slot(drawCard,'inspected')
local cardHeight
local _,state=slot(love.draw,'state')
local function paint()
 labels,drawn={},{}
 love.draw()
 return table.concat(labels,' | '),table.concat(drawn,' | ')
end
paint()
local tileCount=0
for _,path in ipairs(drawn) do
 if path=='art/weathered-flagstones.png' then tileCount=tileCount+1 end
end
assert(tileCount==56,'weathered field must draw the approved art for all 56 hexes')

local function contains(value,substr)
 assert(value:find(substr,1,true),substr..' missing in '..value)
end
for _,class in ipairs({'soldier','ogre','barbarian','assassin','wizard','archer'}) do
 for team=1,2 do
  local id
  for _,u in ipairs(state.units) do if u.class==class and u.owner==team then id=u.id;break end end
  assert(id)
  local u=state.units[id]
  debug.setupvalue(drawCard,inspIndex,id)
  local title,images=paint()
  local _,card=slot(drawCard,'cardBox')
  cardHeight=cardHeight or card.h
  assert(card.h==cardHeight,'all unit cards must have the same height')
  local expected=(team==1 and 'RED ' or 'BLUE ')..class:upper()
  contains(title,expected)
  contains(title,('HEALTH | %d / %d'):format(u.hp,rules.classes[class].hp))
  contains(title,('MOVE | %s'):format(rules.classes[class].move or 'ANY'))
  contains(title,('POWER | %d'):format(rules.classes[class].power))
  contains(title,('SHIELD | %d'):format(rules.classes[class].shield))
  contains(title,('RANGE | %d'):format(class=='archer' and 3 or (class=='wizard' or class=='assassin') and 2 or 1))
  if class=='barbarian' then
    contains(title,'SHIELD | 4')
    contains(title,'Attacks adjacent enemies')
  end
  contains(images,('portraits/%s-%d.png'):format(class,team))
  assert(loaded[('fighters/%s-%d.png'):format(class,team)],'missing battle cutout')
  assert(not title:find('P1',1,true) and not title:find('P2',1,true),
    'outdated player ID displayed')
  assert(not title:find('MARCH',1,true) and not title:find('TELEPORT',1,true),
    'card text should say MOVE')
 end
end
for _,kind in ipairs({'ogre','wizard','archer','fortress'}) do
 for team=1,2 do
  assert(loaded[('art/%s-%d.png'):format(kind,team)],'new token asset not loaded')
 end
end
-- A wounded piece must show current HP, not just maximum HP.
local u=state.units[1]
u.hp=u.hp-5
local max=rules.classes[u.class].hp
debug.setupvalue(drawCard,inspIndex,u.id)
local label=paint()
contains(label,('HEALTH | %d / %d'):format(u.hp,max))
-- The Fortress is also live art, without player numbers.
local fortIndex=slot(drawCard,'inspectedFortOwner')
debug.setupvalue(drawCard,fortIndex,1)
debug.setupvalue(drawCard,inspIndex,'fort')
local ftitle,drawnPaths=paint()
contains(ftitle,'RED FORTRESS')
contains(ftitle,'HEALTH | 50 / 50')
contains(ftitle,'RANGE | 3')
contains(ftitle,'Dormant: arms when attacked')
state.forts[1].armed=true
contains(paint(),'Armed: fires ahead or beside')
contains(drawnPaths,'art/fortress-1.png')
print('PASS: 12 matching profile portraits and board art, live colored names, current/max HP, MOVE/POWER/RANGE/SHIELD, no P1/P2')

local _,drawBoard=slot(love.draw,'drawBoard')
local _,drawDamage=slot(drawBoard,'drawFortressDamage')
local oldLine,oldCircle=g.line,g.circle
local lines,smoke=0,0
g.line=function() lines=lines+1 end
g.circle=function() smoke=smoke+1 end
drawDamage(10,10,14,50)
assert(lines==0 and smoke==0,'full-health fortress should be intact')
drawDamage(10,10,14,21)
assert(lines>0 and smoke==0,'chipped fortress should show cracks only')
drawDamage(10,10,14,20)
assert(smoke>0,'low-health fortress should show smoke')
g.line,g.circle=oldLine,oldCircle

local red,blue=state.units[12],state.units[27]
red.hp,blue.hp,state.forts[2].hp=4,4,12
pulses={}
paint()
assert(#pulses==3,'both teams and the Fortress must pulse at critical health')
local dim=pulses[1]
love.update(.3125)
pulses={}
paint()
assert(#pulses==3 and pulses[1]>dim+.20,'critical glow should visibly pulse')
for _=1,2 do
 local move
 for _,action in ipairs(rules.actions(state)) do
  if action.type=='move' and action.id~=red.id and action.id~=blue.id then move=action;break end
 end
 assert(move and rules.apply(state,move))
 pulses={}
 paint()
 assert(#pulses==3,'critical health must keep pulsing after either side takes a turn')
end
red.hp,blue.hp,state.forts[2].hp=5,0,13
pulses={}
paint()
assert(#pulses==0,'critical glow should stop above a quarter health or when defeated')
print('PASS: critical-health glow pulses for both teams and Fortresses')

-- Fortress combat uses the same cutouts as the cinematic duel.
local overlayIndex=slot(love.draw,'overlay')
for _,attackerClass in ipairs({'fortress','soldier'}) do
 for side=1,2 do
  local defenderClass=attackerClass=='fortress' and 'soldier' or 'fortress'
  debug.setupvalue(love.draw,overlayIndex,{type='battle',elapsed=3.3,event={
   type='attack',actor=side,attackerClass=attackerClass,defenderClass=defenderClass,
   roll=9,shield=3,landed=true,damage=8,attackerHpStart=rules.classes[attackerClass].hp,
   defenderHpStart=rules.classes[defenderClass].hp,defenderHpEnd=rules.classes[defenderClass].hp-8,
  }})
  local _,images=paint()
  local keep=attackerClass=='fortress' and side or 3-side
  contains(images,('art/siege-keep-%d.png'):format(keep))
 end
end
print('PASS: both fortresses use the Final Siege cutouts when attacking or defending')

local siege={deathMatch=true,start={9,12},volleys={
  {a=5,b=5,hit=0,hp={9,12}},{a=11,b=4,hit=1,hp={9,0}},
}}
local view={type='siege',elapsed=.5,siege=siege}
debug.setupvalue(love.draw,overlayIndex,view)
local opening=paint()
contains(opening,'FINAL SIEGE')
contains(opening,'DEATH MATCH')
contains(opening,'HIGH ROLL WINS')
view.elapsed=1.4
contains(paint(),'TIE  •  REROLL')
view.elapsed=2.35+2.12
local resolved=paint()
contains(resolved,'RED WINS')
contains(resolved,'BLUE  0 / 50')
siege.deathMatch=false
view.elapsed=.5
local standard=paint()
contains(standard,'VOLLEY 1')
assert(not standard:find('DEATH MATCH',1,true))
print('PASS: Final Siege labels distinguish the deciding roll, tie, and ordinary volleys')
