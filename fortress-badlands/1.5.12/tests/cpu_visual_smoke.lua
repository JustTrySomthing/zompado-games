package.path='./?.lua;'..package.path
local saved,texts={},{}
local width,height=390,740
local now=0
love={graphics={},timer={getTime=function()return now end},math={random=function(a,b)
  if a and b then return math.random(a,b) elseif a then return math.random(a) else return math.random() end end},
 filesystem={createDirectory=function()return true end,getInfo=function(k)return saved[k] and {type='file'} end,
  write=function(k,v)saved[k]=v;return true end,read=function(k)return saved[k] end,remove=function(k)saved[k]=nil;return true end}}
local g=love.graphics
for _,name in ipairs({'setColor','setFont','polygon','setLineWidth','circle','rectangle','line','draw'}) do g[name]=function(...) end end
g.printf=function(t) texts[#texts+1]=tostring(t) end
g.newFont=function(size)return {size=size} end
g.newImage=function(path)
 local w,h=path=='art/board.png' and 700 or 144,path=='art/board.png' and 984 or 144
 return {getDimensions=function()return w,h end,getWidth=function()return w end,setFilter=function()end}
end
g.getDimensions=function()return width,height end
local mode='solo'
local settingsRequest, fresh
package.preload.zompa=function()return {mode=function()return mode,false end,
 saveSession=function(v)saved.session=v;return true end,
 settingsRequest=function()return settingsRequest end,
 loadSession=function()if not fresh then return saved.session or 'v17|123|' end end,clearSession=function()saved.session=nil;return true end,
 audio=function()return {update=function()end}end}end
local rules=require('rules')
dofile('main.lua');love.load()
local function paint() texts={};love.draw();return table.concat(texts,' ') end
local function tapXY(x,y) now=now+.16; love.touchpressed(1,x,y) end
local ui=require('tests.ui_geometry')
local function tapCell(r,c) tapXY(ui.cell(love,r,c)) end
local function getState()
 for i=1,60 do local name,value=debug.getupvalue(love.draw,i)
  if name=='state' then return value end if not name then break end end
 error('state not found')
end
local state=getState()
tapCell(7,1);paint();tapCell(6,1);paint();tapXY(ui.boxCenter(ui.button(love,'actionBox')))
assert(state.moves==1 and state.turn==2)
assert(paint():find('RED KINGDOM MOVES',1,true),'human move should be visible')
love.update(.4)
assert(paint():find('RED KINGDOM MOVES',1,true),'movement should last multiple frames')
love.update(.62)
assert(not paint():find('RED KINGDOM MOVES',1,true),'movement must finish')
love.update(1.12)
assert(state.moves==2,'CPU did not take a turn')
assert(paint():find('BLUE KINGDOM MOVES',1,true),'CPU should visually travel, not teleport')
local player1=state.units[1]
love.update(.3)
assert(state.moves==2,'no double CPU turn during animation')
print('PASS: both player and CPU move visibly, with a readable action message and no double CPU turn')

local fx=require('movement_fx')
local path={{r=5,c=2},{r=5,c=3},{r=5,c=4}}
local last
local function center(r,c) return c*30,r*30 end
local wizard=fx.new({id=3,route={path[1],path[3]}},'wizard')
local function token(x,y,scale,alpha)
 last={x=x,y=y,scale=scale,alpha=alpha}
end
wizard.elapsed=wizard.travel*.23
fx.draw(g,wizard,center,20,token)
assert(last.x==60 and last.alpha<1,'Wizard should dissolve in place')
wizard.elapsed=wizard.travel*.60
fx.draw(g,wizard,center,20,token)
assert(last.x==120 and last.alpha<1,'Wizard should reform directly at the destination')
for _,class in ipairs({'soldier','ogre','barbarian','archer','assassin','wizard'}) do
 local motion=fx.new({id=3,route=path},class)
 local cues={}
 local function record(cue) cues[#cues+1]=cue end
 assert(not fx.update(motion,motion.travel-.001,record) and #cues==0)
 assert(not fx.update(motion,.002,record))
 assert(fx.update(motion,1,record) and #cues==1 and cues[1]=='move-'..class)
end
print('PASS: Wizard moves between endpoints and each landing plays its own cue once')

local ogre=fx.new({id=7,route=path},'ogre')
local x,y=fx.shake(ogre,20)
assert(x==0 and y==0,'board must stay steady before landing')
ogre.elapsed=ogre.travel+.06
x,y=fx.shake(ogre,20)
assert(math.abs(x)+math.abs(y)>0 and math.abs(x)+math.abs(y)<4)
ogre.elapsed=ogre.duration
x,y=fx.shake(ogre,20)
assert(x==0 and y==0,'landing shake must end before control returns')

-- Start from an otherwise empty board and run the actual attack, battle UI,
-- defending turn and boulder tap path in both local modes.
local newBoard=rules.new
local function soldierSiege(seed,first)
  local board=newBoard(seed,first)
  for _,unit in ipairs(board.units) do unit.hp=0 end
  local soldier=board.units[27]
  soldier.hp,soldier.r,soldier.c=16,10,0
  return board
end
rules.new=soldierSiege
local function confirm()
  paint()
  tapXY(ui.boxCenter(assert(ui.button(love,'actionBox'))))
end
local function continueBattle()
  love.update(2)
  love.update(10)
  assert(paint():find('CONTINUE',1,true))
  tapXY(ui.boxCenter(assert(ui.upvalue(love.draw,'overlay').button)))
  love.update(2)
end
for _,localMode in ipairs({'solo','local'}) do
  mode=localMode
  saved.session='v22|1|2|0|0|0|0|'
  love.load()
  local endgame=getState()
  local fort=endgame.forts[1]
  assert(not fort.armed and rules.count(endgame,1)==0 and rules.count(endgame,2)==1)
  if mode=='solo' then love.update(1.2)
  else tapCell(10,0);tapCell(10,1);confirm() end
  assert(endgame.moves==1 and fort.armed and fort.hp==42 and endgame.turn==1)
  continueBattle()
  assert(endgame.moves==1 and endgame.turn==1,'an armed Fortress with a flank shot must not auto-pass')
  tapCell(10,1)
  tapCell(10,0)
  assert(paint():find('ATTACK NOW',1,true))
  assert(endgame.moves==1,'preview must not spend the turn')
  confirm()
  assert(endgame.moves==2 and endgame.turn==2 and endgame.last.attackerClass=='fortress')
  assert(endgame.units[27].hp==8,'boulder should damage the last Soldier')
  continueBattle()
end

-- A side genuinely out of range still passes, and the handoff tells players why.
mode='local'
saved.session='v22|1|2|0|0|0|0|A27_10_1'
love.load()
local noTarget=getState()
noTarget.units[27].r,noTarget.units[27].c=6,1
tapCell(10,1)
assert(paint():find('NO ENEMIES IN BOULDER RANGE',1,true))
love.update(.4)
assert(noTarget.last.type=='pass' and noTarget.turn==2)
assert(paint():find('Red passes: no legal action',1,true))

-- A 1.0.0 save can contain a now-obsolete forced pass. Preserve it on
-- restore, while rejecting the same pass as a new local or online action.
local oldSave='v22|1|2|0|0|0|0|A27_10_1,P,A27_10_1'
local loaded=assert(rules.restore(oldSave))
assert(loaded.moves==3 and loaded.turn==1 and loaded.forts[1].armed)
assert(not rules.apply(loaded,{type='pass'}),'live defender must get the turn')
assert(not rules.replay(1,{'A27_10_1','P'},2),'online replay must reject the now-illegal pass')
assert(rules.apply(loaded,{type='attack',id=loaded.forts[1].id,r=10,c=0}))
assert(rules.restore(rules.serialize(loaded)),'a new shot must replay after old passes')

-- A repelled first strike arms either Fortress, including at the flank.
for owner=1,2 do
  local board=newBoard(2,3-owner)
  for _,unit in ipairs(board.units) do unit.hp=0 end
  local fort=board.forts[owner]
  local enemy=board.units[owner==1 and 27 or 12]
  enemy.hp,enemy.r,enemy.c=16,fort.r,fort.c-1
  local ok,hit=rules.apply(board,{type='attack',id=enemy.id,r=fort.r,c=fort.c})
  assert(ok and hit.damage==0 and fort.armed and fort.hp==50)
  assert(rules.attacks(board,fort.id)[rules.key(enemy.r,enemy.c)])
  local reply=require('cpu')(board,math.random)
  assert(reply.type=='attack' and reply.id==fort.id,'CPU can use either Fortress to defend')
end
rules.new=newBoard
print('PASS: solo and pass-and-play Fortress defends against the last Soldier, old saves replay, and repelled attacks arm either Fortress')

-- Match Setup owns variants before play in both offline modes.
local variantsUI=require('variant_ui')
local drawWall=variantsUI.wall
local wallSections
variantsUI.wall=function(...)
  wallSections=wallSections+1
  return drawWall(...)
end
local drawRingWall=variantsUI.ringWall
variantsUI.ringWall=function(...)
  wallSections=wallSections+1
  return drawRingWall(...)
end
g.push,g.pop,g.translate,g.scale,g.rotate=function()end,function()end,function()end,function()end,function()end
for _,localMode in ipairs({'solo','local'}) do
  for _,layout in ipairs({
    {id='skirmish',troops=12,crates=2},
    {id='narrows',troops=14,crates=3},
    {id='corners',troops=14,crates=4},
  }) do
    mode,fresh=localMode,true
    wallSections=0
    love.load()
    love.update(4.4)
    assert(paint():find('Start Game',1,true))
    local intro=ui.upvalue(love.draw,'intro')
    tapXY(ui.boxCenter(assert(intro.start)))
    assert(paint():find('Match Setup',1,true))
    local settings=ui.upvalue(love.draw,'timers').settings
    local function setupTap(key)
      tapXY(ui.boxCenter(assert(settings.hits[key],key)))
      paint()
    end
    assert(settings.options.board=='classic')
    setupTap('picker')
    setupTap(layout.id)
    setupTap('advanced')
    assert(not settings.hits.crateCount1)
    for _,key in ipairs({'crates','destroyCrates','wall','wallHealth1','overWall'}) do setupTap(key) end
    assert(wallSections>0 and not next(getState().walls),'preview must be live and isolated')
    setupTap('back')
    assert(not settings.open and ui.upvalue(love.draw,'intro'))
    tapXY(ui.boxCenter(assert(intro.start)))
    paint()
    setupTap('continue')
    local game=getState()
    assert(game.boardId==layout.id and #game.units==layout.troops)
    assert(game.options.wall and game.options.crates and game.options.destroyCrates and game.options.overWall)
    assert(game.options.crateCount==layout.crates and game.options.wallHealth==17)
    local brief=ui.upvalue(love.draw,'overlay')
    assert(brief.type=='brief' and paint():find('This Match Includes',1,true))
    local normalW,normalH=width,height
    g.push,g.pop,g.translate,g.scale=function()end,function()end,function()end,function()end
    width,height=240,300
    love.resize(width,height)
    paint()
    local button=assert(brief.button)
    assert(button.y+button.h<=ui.layout(love).h,'Continue must fit on a short viewport')
    local back=assert(brief.backButton)
    assert(back.x+back.w<button.x)
    tapXY(ui.boxCenter(back))
    assert(paint():find('Match Setup',1,true))
    assert(settings.options.board==layout.id and settings.options.wall)
    setupTap('continue')
    fresh=false
    love.load()
    assert(getState().boardId==layout.id,'reopen must recover the confirmed battlefield')
    assert(getState().seed==game.seed and getState().options.crateCount==layout.crates)
    assert(paint():find('This Match Includes',1,true),'resume the rules summary before initiative')
    local function currentOverlay() return ui.upvalue(love.draw,'overlay') end
    tapXY(ui.boxCenter(currentOverlay().button))
    width,height=normalW,normalH
    love.resize(width,height)
    love.load()
    assert(paint():find('Roll Dice',1,true),'reopen must wait for the roll after reviewing the summary')
    local opening=currentOverlay()
    assert(opening.backButton.x+opening.backButton.w<opening.button.x)
    tapXY(ui.boxCenter(opening.backButton))
    assert(currentOverlay().type=='brief' and paint():find('This Match Includes',1,true))
    tapXY(ui.boxCenter(currentOverlay().button))
    paint()
    tapXY(ui.boxCenter(currentOverlay().button))
    love.load()
    assert(currentOverlay().type=='opening' and currentOverlay().elapsed==0,'reopen the same committed roll')
    assert(getState().first==game.first)
    love.update(120)
    love.load()
    assert(not currentOverlay() and getState().boardId==layout.id and getState().first==game.first)
    assert(getState().moves==0 and not ui.upvalue(love.draw,'intro'),'the first turn is saved before any move')
    settingsRequest=99
    love.update(.2)
    assert(not ui.upvalue(love.draw,'timers').settings.open,'host settings no longer open match rules')
  end
end
variantsUI.wall=drawWall
variantsUI.ringWall=drawRingWall
print('PASS: match setup, live battlefield previews, Back, Continue and scoped settings in both offline modes')
