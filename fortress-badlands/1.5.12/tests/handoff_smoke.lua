-- Approved Fortress UI handoff regression: dynamic winner/bonus phases.
-- Runs without Android, with the same LÖVE APIs mocked as other tests.
package.path='./?.lua;'..package.path
local g={};local rendered={}
local fighters={}
local played={}
local now=0
love={graphics=g,timer={getTime=function()return now end},
 math={random=function(a,b) if a and b then return math.random(a,b) end
   if a then return math.random(a) end return math.random() end},
 filesystem={getInfo=function()return nil end,createDirectory=function()return true end,
 write=function()return true end,read=function()return nil end}}
love.audio={newSource=function(path)
 return {isPlaying=function()return true end,tell=function()return 0 end,setLooping=function()end,setVolume=function()end,stop=function()end,play=function() played[path]=(played[path] or 0)+1 end}
end}
for _,n in ipairs({'setColor','setFont','polygon','setLineWidth','circle',
 'rectangle','line','draw','setStencilTest'}) do g[n]=function()end end
g.printf=function(s) rendered[#rendered+1]=tostring(s) end
g.draw=function(image,x,y,angle,sx)
 if image.path:find('^fighters/') then fighters[image.path]={x=x,angle=angle,sx=sx} end
end
g.newFont=function(sz)return {size=sz} end
g.newImage=function(path)
 local w=path=='art/board.png' and 984 or 144
 local h=path=='art/board.png' and 1383 or 144
 return {path=path,getDimensions=function()return w,h end,getWidth=function()return w end,
  setFilter=function()end}
end
g.stencil=function(fn)fn()end
g.getDimensions=function()return 390,700 end
package.preload.zompa=function()return {
 mode=function()return 'solo',false end,
 audio=function()return {update=function()end,register=function(_,source)return source end}end,
 loadSession=function()return 'v20|123|1|0|0|' end,saveSession=function()return true end,
 clearSession=function()return true end
}end
local rules=require('rules')
dofile('main.lua')
love.load()
local function upval(name,fn)
 for i=1,100 do
  local key,v=debug.getupvalue(fn or love.draw,i)
  if key==name then return i,v end
  if not key then break end
 end
 error('missing draw upvalue '..name)
end
local index=upval('overlay')
local function setOverlay(o)
 debug.setupvalue(love.draw,index,o)
end
local function paint()
 rendered,fighters={},{}
 love.draw()
 return table.concat(rendered,' | ')
end
local function expect(output,needle)
 assert(output:find(needle,1,true),needle..' missing in '..output)
end
local event={type='attack',actor=1,attackerClass='assassin',defenderClass='soldier',
 attackerHpStart=10,defenderHpStart=10,defenderHpEnd=0,roll=12,shield=2,
 landed=true,damage=10,defeated=true,heal={roll=4,actual=4}}
local o={type='battle',elapsed=.35,event=event}
setOverlay(o)
local ready=paint()
expect(ready,'Ready for Combat')
expect(ready,'D12')
assert(not o.button)
o.elapsed=1.2
expect(paint(),'ATTACK ROLL')
assert(not o.button)
o.elapsed=2.45
paint()
local left,right='fighters/assassin-1.png','fighters/soldier-2.png'
local leftX,rightX=fighters[left].x,fighters[right].x
assert(fighters[left].sx>0 and fighters[right].sx<0)
assert(not played['audio/assassin.wav'])
love.update(.78)
local impact=paint()
expect(impact,'-10')
expect(impact,'0 / 16 HEALTH')
assert(played['audio/assassin.wav']==1,'class impact must play with damage')
assert(played['audio/hurt-1.wav']==1,'landed hits on troops add a short vocal effort')
love.update(.01)
assert(played['audio/assassin.wav']==1,'impact must play once')
assert(played['audio/hurt-1.wav']==1 and not played['audio/hurt-2.wav'],'one voice per landed impact')

assert(fighters[left].x>leftX and fighters[left].angle>0)
assert(fighters[right].x>rightX)
o.elapsed=4.65
local result=paint()
expect(result,'VICTORY')
expect(result,'Your Foe is Defeated')
expect(result,'10 DAMAGE')
assert(not o.button,'pause before showing the reward')
love.update(1.35)
local reward=paint()
expect(reward,'VICTORY REWARD')
expect(reward,'Roll for Reward')
love.update(5)
assert(o.button and not o.bonusElapsed,'Victory should wait for the human reward roll')
love.touchpressed(1,o.button.x+o.button.w*.5,o.button.y+o.button.h*.5)
assert(o.bonusElapsed==0)
expect(paint(),'VICTORY REWARD')
expect(paint(),'Rolling for Health')
love.update(1.35)
expect(paint(),'Rolling for Health')
assert(not o.button,'the roll should be visible before the reward amount')
love.update(2)
expect(paint(),'+4 HEALTH')
assert(not o.button,'the reward amount should be visible before Continue')
love.update(.45)
expect(paint(),'CONTINUE')

local blocked={type='attack',actor=2,attackerClass='archer',defenderClass='wizard',
 attackerHpStart=14,defenderHpStart=18,roll=4,shield=4,landed=false}
setOverlay({type='battle',elapsed=4.84,event=blocked})
local repelled=paint()
local miss={type='battle',elapsed=3.03,event=blocked}
setOverlay(miss)
love.update(.17)
assert(played['audio/blocked.wav']==1 and not played['audio/hurt-2.wav'],
 'a shield block must not trigger a vocal effort')
expect(repelled,'ATTACK REPELLED')
assert(not repelled:find('Turn over',1,true))
expect(repelled,'CONTINUE')

local cpu={type='battle',elapsed=4.65,event=event}
event.actor=2
setOverlay(cpu)
love.update(1.26)
expect(paint(),'Blue earned a Health roll')
assert(not cpu.bonusElapsed)
love.update(1.1)
assert(cpu.bonusElapsed==0)
expect(paint(),'VICTORY REWARD')
love.update(3.8)
expect(paint(),'CONTINUE')
print('PASS: impact animation, readable damage, repelled attack and player/CPU D12 victory bonus')

local full={type='attack',actor=1,attackerClass='archer',defenderClass='soldier',
 attackerHpStart=14,defenderHpStart=1,defenderHpEnd=0,roll=12,shield=2,
 landed=true,damage=1,defeated=true,fullHealth=true}
local fullView={type='battle',elapsed=5.78,event=full}
setOverlay(fullView)
local result=paint()
expect(result,'VICTORY')
expect(result,'Your Foe is Defeated')
expect(result,'AMAZING')
expect(result,'Already at full Health')
expect(result,'No reward roll needed')
assert(not fullView.button,'full-health notice should get a hold before Continue')
love.update(.62)
expect(paint(),'CONTINUE')
assert(not fullView.bonusElapsed)
print('PASS: full-health result announces that no roll is needed before offering Continue')


local finishingStrike={type='battle',elapsed=1.34+3.18-.26,
  event={actor=1,attackerClass='assassin',defenderClass='soldier',
    attackerHpStart=4,defenderHpStart=4,deathMatch={winner=1,rounds={{8,7}}}}}
setOverlay(finishingStrike)
paint()
local restingLeft,restingRight=fighters[left].x,fighters[right].x
finishingStrike.elapsed=1.34+3.18-.02
paint()
assert(fighters[left].x>restingLeft and fighters[right].x==restingRight,'only the Death Match winner should lunge')
finishingStrike.event.deathMatch.winner=2
finishingStrike.event.deathMatch.rounds={{7,8}}
paint()
assert(fighters[left].x==restingLeft and fighters[right].x<restingRight,'a winning defender can deliver the finishing strike')

local duel={type='attackNotice',quick=true,elapsed=0,event={deathMatch={rounds={{8,7}}}}}
setOverlay(duel)
love.update(1.2)
assert(duel.type=='attackNotice' and duel.elapsed==1.2)
love.update(.17)
assert(duel.type=='battle' and duel.elapsed==0)
love.update(.6)
assert(duel.elapsed==.3)
local siege={type='siege',elapsed=0,siege={volleys={{hit=1}}}}
setOverlay(siege)
love.update(3)
assert(siege.elapsed==1.5)
assert(not played['audio/fortress.wav'],'volley hit must not play before its slowed impact')
love.update(1)
assert(siege.elapsed==2 and played['audio/fortress.wav']==1)
setOverlay(nil)
local _,state=upval('state')
state.winner,state.finish=1,'siege'
love.update(1)
assert(not played['audio/collapse.wav'],'Final Siege collapse must hold for the slowed introduction')
love.update(.6)
assert(played['audio/collapse.wav']==1)
print('PASS: Death Match and Final Siege run at half speed alongside ordinary combat at full speed')

-- Exercise both kingdom outcomes from each player perspective.
for _,name in ipairs({'push','pop','translate','rotate','scale','shear'}) do
 g[name]=function()end
end
g.newFont=function(sz)
 return {size=sz,getWidth=function(_,label)return #label*sz*.55 end}
end
local keeps={}
g.draw=function(image,x)
 local side=image.path:match('^art/siege%-keep%-(%d)%.png$')
 if side then keeps[tonumber(side)]=x end
 if image.path:match('^art/finish%-') then rendered[#rendered+1]=image.path end
end
love.resize(390,700)
local drawMode=upval('mode')
local drawSide=upval('onlineSide')
local finishTime=upval('finishElapsed',love.update)
local animation=upval('animationTime',love.update)
local _,timers=upval('timers')
local skullColor,skullRadius
g.setColor=function(r,green,blue,alpha)
 skullColor=r==.94 and green==.71 and blue==.55 and alpha>0
end
g.circle=function(_,_,_,radius)
 if skullColor then skullRadius=radius end
end
local function radiusAt(t,phase)
 skullRadius=nil
 debug.setupvalue(love.update,finishTime,t)
 debug.setupvalue(love.update,animation,phase)
 paint()
 return skullRadius
end
local victoryRadius,defeatRadius
for _,view in ipairs({{'solo',1},{'local',0},{'online',1},{'online',2}}) do
 debug.setupvalue(love.draw,drawMode,view[1])
 debug.setupvalue(love.draw,drawSide,view[2]~=0 and view[2] or nil)
 if view[1]=='online' then debug.setupvalue(love.draw,upval('onlineReady'),true) end
 for owner=1,2 do
  state.winner=owner
  local lost=view[2]~=0 and view[2]~=owner
  for _,t in ipairs({.10,.32,.57,.74}) do
   debug.setupvalue(love.update,finishTime,t)
   local oldX=keeps[3-owner]
   paint()
   if t>.10 then assert(keeps[3-owner]==oldX,'Damaged keep must shake in place') end
  end
  played={}
  timers.poll=-10
  debug.setupvalue(love.update,finishTime,1.43)
  love.update(.06)
  assert(played['audio/'..(lost and 'defeat' or 'victory')..'.wav']==1)
  debug.setupvalue(love.update,finishTime,1.91)
  love.update(.06)
  assert((played['audio/firework.wav']==1)==not lost)
  local screen=paint()
  expect(screen,'art/finish-'..(lost and 'defeat' or 'victory')..'.png')
  expect(screen,(owner==1 and 'RED' or 'BLUE')..' KINGDOM WINS')
  local early=assert(radiusAt(1.76,0))
  local late=radiusAt(6,0)
  if lost then
   defeatRadius=early
   assert(not late,'Defeat skull should finish fading')
  else
   victoryRadius=early
   assert(late==early,'Victory skull should stay visible at the end')
   love.update(1.4)
   skullRadius=nil
   paint()
   assert(skullRadius and skullRadius>late,'Victory skull should keep pulsing after the finale clock stops')
  end
 end
end
assert(victoryRadius<defeatRadius,'Victory skull should use the smaller size')
print('PASS: both kingdoms get the appropriate finale art, audio and pulsing skull in every perspective')
