package.path='./?.lua;'..package.path
local saved,texts={},{}
local now=0
local labels,rectangles={},{}
local currentFont
local draws=0
local fortressSprites=0
local portraitSprites=0
local maskCalls=0
love={graphics={},timer={getTime=function()return now end},math={random=function(a,b)
  if a and b then return math.random(a,b) elseif a then return math.random(a) else return math.random() end end},
 filesystem={createDirectory=function()return true end,getInfo=function(k)return saved[k] and {type='file'} end,
  write=function(k,v)saved[k]=v;return true end,read=function(k)return saved[k] end,
  remove=function(k)saved[k]=nil;return true end}}
local g=love.graphics
for _,name in ipairs({'setColor','setFont','polygon','setLineWidth','circle','line'}) do g[name]=function(...) end end
g.rectangle=function(mode,x,y,w,h)
  if mode=='line' then rectangles[#rectangles+1]={x=x,y=y,w=w,h=h} end
end
g.setFont=function(font)currentFont=font end
g.printf=function(t,x,y,w)
  texts[#texts+1]=tostring(t)
  labels[t]={x=x,y=y,w=w,h=currentFont.size}
end
g.newFont=function(size)assert(size>=10);return {size=size} end
-- Mock the host stencil API to exercise badge-only clipping.
g.stencil=function(fn,action,value)maskCalls=maskCalls+1;fn()end
g.setStencilTest=function(...)end
g.newImage=function(path)
  local w,h=path=='art/board.png' and 700 or 144,path=='art/board.png' and 984 or 144
  if path:find('^portraits/') then w,h=240,240 end
  return {path=path,getDimensions=function()return w,h end,
    getWidth=function()return w end,setFilter=function()end}
end
g.draw=function(img,...)
 draws=draws+1
 if img and img.path and img.path:find('^art/fortress%-') then
   fortressSprites=fortressSprites+1
 end
 if img and img.path and img.path:find('^portraits/') then
   portraitSprites=portraitSprites+1
 end
end
local width,height=390,700
g.getDimensions=function()return width,height end
package.preload.zompa=function()return {mode=function()return 'solo',false end,
 saveSession=function(v)saved.session=v;return true end,
 loadSession=function()return saved.session end,clearSession=function()saved.session=nil;return true end,
 audio=function()return {update=function()end}end}end
local rules=require('rules')
local ui=require('tests.ui_geometry')
dofile('main.lua');love.load()
local opening=ui.upvalue(love.draw,'overlay')
assert(opening.type=='opening')
assert(opening.opening.first==ui.upvalue(love.draw,'state').turn)
local function paint() texts,labels,rectangles={},{},{};draws,fortressSprites=0,0;love.draw();return table.concat(texts,' ') end
local function tapXY(x,y) now=now+.17; love.touchpressed(1,x,y) end
local function tapCell(r,c) tapXY(ui.cell(love,r,c)) end
local function tapButton(name)
  paint()
  tapXY(ui.boxCenter(ui.button(love,name)))
end
local function tapConfirm() tapButton('actionBox') end
local function tapCancel() tapButton('cancelBox') end
local function has(t,word) assert(t:find(word,1,true),'missing '..word..' in '..t:sub(1,700)) end
local function getState()
  for i=1,60 do local name,val=debug.getupvalue(love.draw,i)
    if name=='state' then return val end if not name then break end end
  error('game state inaccessible for UI test')
end
-- A completed move or attack stays in history without drawing on the idle board.
local function expectCleanHandoff(state,kind)
  assert(state.last and state.last.type==kind)
  assert(not ui.upvalue(love.draw,'overlay'),'handoff check needs the idle board')
  local calls={}
  local circle,line,polygon=g.circle,g.line,g.polygon
  local function count() calls[#calls+1]=true end
  g.circle,g.line,g.polygon=count,count,count
  paint()
  local withHistory=#calls
  local last=state.last
  state.last=nil
  calls={}
  paint()
  state.last=last
  g.circle,g.line,g.polygon=circle,line,polygon
  assert(withHistory==#calls,'last '..kind..' left an idle board marker')
end
local state=getState()
love.update(100)
local welcome=paint()
for _,label in ipairs({'Start Game','How to Play','You · Red','CPU · Blue'}) do has(welcome,label) end
local intro=ui.upvalue(love.draw,'intro')
tapXY(ui.boxCenter(intro.guide))
local training=paint()
has(training,'Inspect a Piece')
has(training,'Red Soldier')
assert(not training:find('Archer',1,true),'the Archer must not be introduced during inspection')
tapXY(ui.boxCenter(intro.close))
has(paint(),'Start Game')
tapXY(ui.boxCenter(intro.guide))
local practice=intro.help
tapCell(0,1)
assert(practice.step=='inspect','the tutorial must wait for the marked Soldier')
assert(practice.board.units[4].hp==0 and practice.board.units[27].hp==0,
  'future practice units must be hidden')
tapCell(7,1)
for index,stat in ipairs({'Health','Move','Power','Range','Shield'}) do
  local lesson=paint()
  has(lesson,'RED SOLDIER')
  has(lesson,('%s  ·  %d / 5'):format(stat,index))
  tapXY(ui.boxCenter(practice.button))
end
has(paint(),'Choose a Destination')
local destination=next(rules.moves(practice.board,12))
tapCell(rules.fromkey(destination))
has(paint(),'Move Here')
tapXY(ui.boxCenter(practice.button))
has(paint(),'Move Confirmed')
assert(practice.board.units[4].hp==0,'complete the move before revealing the Archer')
love.update(1)
has(paint(),'Select Your Archer')
assert(practice.board.units[27].hp==0,'select the Archer before revealing the target')
tapCell(6,4)
has(paint(),'Choose a Target')
tapCell(4,3)
has(paint(),'Attack Now')
has(paint(),'Archer Power 6. Target Shield 2.')
tapXY(ui.boxCenter(practice.button))
assert(practice.battle.event.defeated and practice.battle.event.heal.actual>0)
love.update(.1)
has(paint(),'Ready for Combat')
love.update(10)
has(paint(),'Roll for Reward')
has(paint(),'Roll 8 beats Shield 2  ·  6 Health lost')
tapXY(ui.boxCenter(practice.battle.button))
love.update(10)
has(paint(),'+7 HEALTH')
tapXY(ui.boxCenter(practice.battle.button))
has(paint(),'Your Objective')
assert(not practice.button,'inspect the Blue Fortress before starting')
tapCell(10,1)
assert(practice.step=='objective','the Red Fortress is not the training objective')
tapCell(0,1)
has(paint(),'Read the Fortress Card')
tapXY(ui.boxCenter(ui.upvalue(love.draw,'cardBox').expand))
g.push,g.pop,g.translate,g.scale=function()end,function()end,function()end,function()end
g.print=function(value) texts[#texts+1]=tostring(value) end
g.newMesh=function()return {} end
has(paint(),'Status: Dormant')
local expanded=require('piece_detail').bounds
tapXY(expanded.x+348*expanded.scale,expanded.y+25*expanded.scale)
g.push,g.pop,g.translate,g.scale=nil,nil,nil,nil
g.newMesh=nil
has(paint(),'Ready for the Siege')
assert(getState()==state and state.moves==0 and state.units[4].hp==14,
  'practice must leave the live match untouched')
tapXY(ui.boxCenter(practice.button))
has(paint(),'Match Setup')
local setup=ui.upvalue(love.draw,'timers').settings
tapXY(ui.boxCenter(assert(setup.hits.continue)))
has(paint(),'Roll to See Who Goes First')
assert(paint():find('Roll Dice',1,true))
opening=ui.upvalue(love.draw,'overlay')
assert(opening.backButton.x+opening.backButton.w<opening.button.x)
tapXY(ui.boxCenter(opening.backButton))
has(paint(),'Match Setup')
tapXY(ui.boxCenter(assert(setup.hits.continue)))
has(paint(),'Roll Dice')
opening=ui.upvalue(love.draw,'overlay')
state=getState()
assert(opening.elapsed==nil,'opening must wait for the player')
tapXY(ui.boxCenter(opening.button))
assert(opening.elapsed==0)
opening.elapsed=(#opening.opening.rounds-1)*1.65+.85
love.update(2.20)
has(paint(),state.turn==1 and 'You Go First' or 'CPU Goes First')
assert(not opening.button,'the winner is an announcement rather than a tap target')
love.update(.16)
has(paint(),state.turn==1 and 'Your Turn' or "CPU's Turn")
state.turn=1
love.update(1.1)
local idle=paint()
has(idle,'TAP ONE OF YOUR UNITS')
assert(draws>=30,'all 30 living piece sprites must render')
assert(fortressSprites==2,'both fortress sprite assets must render on board')
-- A Fortress can be inspected before choosing a troop.
tapCell(state.forts[2].r,state.forts[2].c)
has(paint(),'BLUE FORTRESS')
assert(state.moves==0)
-- Inspect the opponent: does not spend a turn.
tapCell(2,1)
has(paint(),'ASSASSIN')
assert(maskCalls>0,'inspection should mask the original square tile background')
assert(state.turn==1 and state.moves==0)
-- Inspect a friendly player; the clear unit stats must be visible.
tapCell(7,1)
local info=paint()
for _,v in ipairs({'RED SOLDIER','HEALTH 16 / 16','MOVE 1','POWER 8','SHIELD 2'}) do has(info,v) end
assert(portraitSprites>0,'red side-view portrait must be used in live unit card')
assert(not info:find('P1',1,true) and not info:find('MARCH',1,true),'old P1/MARCH card leaked')
assert(not info:find('CAPTURE RANGE',1,true))
-- Each Fortress overrides the troop card while leaving that troop selected.
tapCell(6,1)
has(paint(),'MOVE HERE')
local escapeX,escapeY=ui.boxCenter(ui.button(love,'cancelBox'))
love.keypressed('escape')
tapXY(escapeX,escapeY)
assert(state.moves==0,'a stale Cancel tap after Escape must be harmless')
tapCell(7,1)
tapCell(6,1)
has(paint(),'MOVE HERE')
state.forts[2].hp=22
tapCell(state.forts[2].r,state.forts[2].c)
local blueFort=paint()
has(blueFort,'BLUE FORTRESS')
has(blueFort,'HEALTH 22 / 50')
has(blueFort,'POWER 8')
assert(not blueFort:find('RED SOLDIER',1,true))
assert(not blueFort:find('ATTACK NOW',1,true) and not blueFort:find('MOVE HERE',1,true))
tapCell(state.forts[1].r,state.forts[1].c)
local redFort=paint()
has(redFort,'RED FORTRESS')
has(redFort,'HEALTH 50 / 50')
has(redFort,'POWER 8')
assert(state.turn==1 and state.moves==0,'inspecting a Fortress must not spend a turn')
state.forts[2].hp=50
-- Tapping a glowing empty cell previews. It must not commit until the Move button.
tapCell(6,1)
has(paint(),'MOVE HERE')
assert(state.turn==1 and state.moves==0)
tapCancel()
assert(state.moves==0)
tapCell(6,1);tapConfirm()
assert(state.turn==2 and state.moves==1)
assert(saved.session,'must save immediately even during movement animation')
local advancing=paint()
has(advancing,'RED KINGDOM MOVES')
love.update(1.1)
has(paint(),"Blue's Turn")
love.update(1.1)
expectCleanHandoff(state,'move')
-- Confirming an attack starts the battle sequence and spends one turn.
for _,u in ipairs(state.units) do if u.id~=8 and u.id~=23 then u.hp=0 end end
local a,b,other=state.units[8],state.units[23],state.units[27]
a.r,a.c,a.hp=4,1,10;b.r,b.c,b.hp=4,3,10
other.r,other.c,other.hp=4,0,8
local targetRims,availableRims,ripples={},{},{}
local markerColor
local oldColor,oldPolygon=g.setColor,g.polygon
g.setColor=function(r,green,blue)
  markerColor=r==.84 and green==.97 and blue==1 and targetRims
    or r==.66 and green==.86 and blue==.94 and availableRims
    or r==.75 and green==.94 and blue==1 and ripples
end
g.polygon=function(mode,vertices)
  if markerColor and mode=='line' and type(vertices)=='table' then
    markerColor[#markerColor+1]=vertices
  end
end
local function paintMarkers()
  targetRims,availableRims,ripples={},{},{}
  paint()
end
local function expectRim(row,col)
  paintMarkers()
  local x,y=ui.cell(love,row,col)
  local marker=targetRims[1]
  assert(#targetRims==1 and #availableRims==1,'chosen and available rims must be distinct')
  assert(math.abs(marker[1]-x)<.01 and marker[2]<y,'the bright rim must follow the chosen target')
end
state.turn,state.moves,state.last,state.winner=1,1,nil,nil
state.rng=1
tapCell(4,1);tapCell(4,3)
local preview=paint()
has(preview,'Target')
has(preview,'BLUE ASSASSIN')
has(preview,'ATTACK NOW')
assert(labels['ATTACK NOW'] and not preview:find('2 HEXES',1,true))
expectRim(4,3)
assert(#ripples==1,'selection starts the first expanding hex')
love.update(.29)
expectRim(4,3)
assert(#ripples==3,'selection emits three staggered expanding hexes')
love.update(1)
expectRim(4,3)
assert(#ripples==0,'the chosen rim stays visible after the animation ends')
tapCell(4,0)
expectRim(4,0)
assert(#ripples==1,'switching targets restarts the animation')
tapCancel()
paintMarkers()
assert(#targetRims==0 and #availableRims==2 and #ripples==0,'cancel restores only the available rims')
g.setColor,g.polygon=oldColor,oldPolygon
other.hp=0
assert(not paint():find('Target',1,true),'Cancel should clear the Target badge')
tapCell(4,3)
tapConfirm()
love.update(.21)
has(paint(),'Red Assassin Attacks')
has(paint(),'Blue Assassin')
love.update(1.44)
love.update(.35)
has(paint(),'Ready for Combat')
has(paint(),'D12')
local battle=ui.upvalue(love.draw,'overlay')
assert(not battle.button,'Ready for Combat should be hands-free')
assert(state.moves==2 and a.c==1)
love.update(.85)
has(paint(),'ATTACK ROLL')
assert(not battle.button)
love.update(3.6)
has(paint(),'VICTORY')
has(paint(),'Your Foe is Defeated')
assert(not battle.button)
love.update(1.35)
has(paint(),'VICTORY REWARD')
has(paint(),'Roll for Reward')
love.update(6)
assert(not battle.bonusElapsed,'Player reward must wait for the button')
tapXY(ui.boxCenter(battle.button))
has(paint(),'Rolling for Health')
assert(not battle.button)
love.update(3.8)
has(paint(),('+'..state.last.heal.actual..' HEALTH'))
has(paint(),'CONTINUE')
assert(ui.layout(love).h-4-(battle.button.y+battle.button.h+3)>=11,
  'Continue frame needs padding inside the battle panel')
tapXY(ui.boxCenter(battle.button))
has(paint(),"Blue's Turn")
love.update(1.1)
expectCleanHandoff(state,'attack')
-- Verify controls and card text against both the viewport and its safe area.
state.units=rules.new(47061).units
love.window={getSafeArea=function() return 0,0,width,height-20 end}
for _,dim in ipairs({{240,320},{280,480},{320,520},{420,850},{390,700},{450,980}}) do
  width,height=dim[1],dim[2]
  love.resize(width,height)
  state.turn=1
  tapCell(7,1)
  tapCell(6,1)
  has(paint(),'MOVE HERE')
  local layout=ui.layout(love)
  local move,hit,range=labels.MOVE,labels.POWER,labels.RANGE
  assert(range and range.y==hit.y and hit.x+hit.w<range.x,'Power and Range should be adjacent')
  local value=labels[tostring(rules.classes.soldier.power)]
  assert(value and value.x>hit.x+hit.w and value.x+value.w<range.x,
    'Power value should be grouped with its label')
  local band
  for _,box in ipairs(rectangles) do
    if box.h==layout.statBandH and box.y<=move.y and box.x<=move.x then band=box;break end
  end
  assert(hit and band,'missing live stat band')
  assert(hit.y-band.y>=4.99 and band.y+band.h-move.y-move.h>=4.99,'stat text touches its border')
  assert(layout.cardY+layout.cardH-band.y-band.h>=7,'stat band touches the outer card')
  assert(layout.cardY+layout.cardH<layout.y,'card overlaps the board')
  for _,name in ipairs({'actionBox','cancelBox'}) do
    local button=ui.button(love,name)
    assert(button.y-(layout.y+layout.boardH)>=15,'leave a gap between the button and the board')
    assert(button.y+button.h+3<=height-20-24,'button frame enters the bottom safety margin')
  end
  tapCancel()
end
-- In range, the enemy Fortress is inspected and still offers a confirmed attack.
for _,u in ipairs(state.units) do u.hp=0 end
local wizard=state.units[3]
wizard.r,wizard.c,wizard.hp=1,1,18
local fort=state.forts[2]
tapCell(wizard.r,wizard.c)
tapCell(fort.r,fort.c)
local attackFort=paint()
has(attackFort,'BLUE FORTRESS')
has(attackFort,'Target')
has(attackFort,'ATTACK NOW')
assert(state.moves==2,'previewing a Fortress attack must not spend a turn')
print('PASS: responsive stat cards, selected target previews and player attack/bonus controls')

-- Reopen a real saved battle with a reward pending, then continue the match.
width,height=390,700
saved.session='v20|4569951|1|0|0|M6_7_5,M18_3_0,M6_5_4,M18_5_0,A6_3_3,A18_7_1,A6_3_3,A18_7_1,A6_3_4,M16_1_0,A6_3_4,M28_4_2,A6_3_4,M24_3_2,M11_7_5,M20_2_2,M2_8_4,A20_5_4,M6_5_3,M21_3_5,A6_4_2,M24_5_2'
love.load()
tapCell(5,3)
tapCell(4,2)
tapConfirm()
local committed=getState()
assert(committed.last.heal and committed.last.heal.actual==3)
assert(saved.session:match('^REWARD:'))
local committedHp=committed.units[6].hp
love.load()
has(paint(),'Roll for Reward')
local resumed=ui.upvalue(love.draw,'overlay')
tapXY(ui.boxCenter(resumed.button))
love.update(3.8)
has(paint(),'+3 HEALTH')
assert(getState().units[6].hp==committedHp,'replaying a reward cannot apply extra healing')
assert(saved.session:match('^REWARD_SHOWN:'))
love.load()
local revealed=paint()
has(revealed,'+3 HEALTH')
has(revealed,'CONTINUE')
assert(not revealed:find('Roll for Reward',1,true),'already rolled rewards must reopen at the result')
resumed=ui.upvalue(love.draw,'overlay')
tapXY(ui.boxCenter(resumed.button))
assert(not saved.session:match('^REWARD'))
love.load()
assert(not paint():find('Roll for Reward',1,true),'continued rewards should not reopen')
print('PASS: unclaimed local rewards survive a reopen without duplicate healing')

-- The duel cue belongs to the confirmed target preview and clears on cancel.
local duelBoard=getState()
for _,unit in ipairs(duelBoard.units) do unit.hp=0 end
duelBoard.turn=1
local attacker,defender=duelBoard.units[3],duelBoard.units[27]
attacker.hp,attacker.r,attacker.c=4,5,2
defender.hp,defender.r,defender.c=4,5,3
local originalMoves=duelBoard.moves
tapCell(5,2)
assert(not paint():find('DEATH MATCH',1,true))
tapCell(5,3)
love.update(.35)
has(paint(),'DEATH MATCH')
has(paint(),'ATTACK NOW')
assert(duelBoard.moves==originalMoves and attacker.hp==4 and defender.hp==4)
tapCancel()
assert(not paint():find('DEATH MATCH',1,true))
defender.hp=5
tapCell(5,3)
assert(not paint():find('DEATH MATCH',1,true))
print('PASS: only a selected Death Match gets a preview, which clears on cancellation')
