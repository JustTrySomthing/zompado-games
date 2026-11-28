local rules = require('rules')
local ui = require('tests.ui_geometry')
local function openingFor(winner)
  for blue=456,600 do
    local seed=(123*181+blue*9973)%2147483647
    if rules.initiative(seed).first==winner then return {123,blue},seed end
  end
  error('missing opening fixture')
end
local nonce,seed=openingFor(1)
local function scenario(accept, seekReward)
  local match=rules.new(seed,1)
  local history={'I'..nonce[1],'I'..nonce[2]}
  local battle
  for _ = 1, 300 do
    local bestMove, bestScore
    for _, action in ipairs(rules.actions(match)) do
      if action.type == 'attack' then
        local after = rules.copy(match)
        local ok, event = rules.apply(after, action)
        if ok and match.turn==1 and accept(event,after) and not after.winner then
          battle = action
          break
        end
        if seekReward and ok and not after.winner then
          local value=60+(event.landed and 8 or 0)+(event.defeated and 4 or 0)
          if not bestScore or value>bestScore then bestMove,bestScore=action,value end
        end
      elseif action.type == 'move' then
        local piece = rules.piece(match,action.id)
        local towardEnemy = match.turn == 1 and piece.r - action.r or action.r - piece.r
        local score = towardEnemy * 10 - math.abs(action.r - 5) - math.abs(action.c - 3)
        if not bestScore or score > bestScore then bestMove, bestScore = action, score end
      end
    end
    if battle then break end
    assert(bestMove, 'could not find legal setup move')
    assert(rules.apply(match, bestMove))
    local token = rules.encode(bestMove)
    history[#history + 1] = token
    if bestMove.type=="attack" then
      history[#history+1]="K"
      if match.last.heal then history[#history+1]="R";history[#history+1]="K" end
      history[#history+1]="C"
    end
  end
  assert(battle and #history >= 2, 'could not reach battle fixture')
  return match,history,battle
end
local function counterattack(state)
  if state.winner then return nil end
  for _,action in ipairs(rules.actions(state)) do
    if action.type=='attack' then
      local trial=rules.copy(state)
      local ok=rules.apply(trial,action)
      if ok and not trial.winner then return action end
    end
  end
end
local match,history,battle=scenario(function(event,after)
  return event.landed and counterattack(after)
end)

local width, height = 390, 700
local paged=false
local function client(side)
  local now, labels = 0, {}
  local outbound,failNextWrite,settingsRequest
  local g = {}
  for _, name in ipairs({'setColor','setFont','polygon','setLineWidth','circle','line','rectangle','push','pop','translate','rotate','scale'}) do
    g[name] = function() end
  end
  g.printf = function(label) labels[label] = true end
  g.newFont = function(size) return {size=size} end
  g.getDimensions = function() return width, height end

  local love = {graphics=g, timer={getTime=function() return now end}, math={random=function() return nonce[side] end}}
  local hostFiles = {open=function(path, mode)
    if path == '/zompado/advanced-settings' and mode=='wb' then
      return {write=function() return true end,close=function() return true end}
    end
    if path == '/zompado/move' then
      assert(mode == 'wb' and not outbound, 'duplicate turn submitted')
      if failNextWrite then
        failNextWrite=false
        return nil,'simulated turn file failure'
      end
      return {write=function(_, value) outbound = value; return true end, close=function() return true end}
    end
    local value
    if path == '/zompado/settings-request' then
      value = settingsRequest and tostring(settingsRequest)
    elseif path == '/zompado/mode' then
      value = 'online'
    elseif path == '/zompado/opponent' then
      value = side==1 and 'Mira Frost' or 'Charles'
    elseif path == '/zompado/match' and not paged then
      value = ('%d:%d:%s'):format(side, (1+#history%2)==side and 1 or 0, table.concat(history, ','))
    elseif paged and path == '/zompado/match-pages' then
      value = ('%d:%d:%d'):format(side, (1+#history%2)==side and 1 or 0, math.ceil(#history/128))
    elseif paged then
      local page=tonumber(path:match('^/zompado/match%-page%-(%d+)$'))
      if page then value=table.concat(history,',',page*128+1,math.min((page+1)*128,#history)) end
    end
    return value and {read=function() return value end, close=function() end}
  end}
  local env = setmetatable({love=love, io=hostFiles}, {__index=_G})
  local sdk = assert(loadfile('zompa.lua', 't', env))()
  env.require = function(name) return name == 'zompa' and sdk or require(name) end
  assert(loadfile('main.lua', 't', env))()
  love.load()

  local c = {}
  function c.board() return ui.upvalue(love.draw,'state') end
  function c.step(dt)
    now = now + dt
    love.update(dt)
    labels = {}
    love.draw()
    return labels
  end
  local function tap(x, y)
    now = now + .17
    love.touchpressed(1, x, y)
  end
  local function cell(r, col) tap(ui.cell(love, r, col)) end
  function c.submit(action,failOnce)
    local piece = rules.piece(match,action.id)
    cell(piece.r, piece.c)
    cell(action.r, action.c)
    local painted = c.step(0)
    if action.type=='attack' then
      assert(painted['ATTACK NOW'])
      assert(painted.Target or painted['Wall Section · Target'])
    elseif action.type=='crate' then
      assert(painted['DESTROY CRATE'] and painted['Mystery Crate'])
      assert(painted['A potion or a bomb?\nOpen it to find out.'])
    else assert(painted['MOVE HERE']) end
    local extra=action.type=='crate' and ui.upvalue(love.draw,'timers').potionAttackBox
    local x,y = ui.boxCenter(extra or ui.button(love, 'actionBox'))
    if failOnce then
      failNextWrite=true
      tap(x,y)
      assert(not outbound and c.step(0)['Could not send. Tap again to retry.'])
      assert(ui.button(love,'actionBox'),'failed send must keep the target available')
    end
    tap(x,y)
    tap(x,y) -- Repeated confirmation must not submit a second turn.
    assert(outbound == '-:' .. rules.encode(action), tostring(outbound))
    history[#history + 1] = outbound:sub(3)
    outbound = nil
    assert(rules.apply(match, action))
  end
  function c.ackBrief(resurrection)
    local labels=c.step(0)
    assert(labels['This Match Includes'])
    if resurrection then assert(labels['Soldier Resurrection'])
    else assert(labels['Each crate holds a potion or a bomb.'] and labels['Border Wall']) end
    tap(ui.boxCenter(assert(ui.upvalue(love.draw,'overlay').button)))
  end
  function c.chooseResurrection(action)
    local piece=c.board().units[action.id]
    cell(piece.r,piece.c)
    cell(action.r,action.c)
    assert(c.step(0)['MOVE HERE'])
    tap(ui.boxCenter(ui.button(love,'actionBox')))
    assert(not outbound and c.board().moves==0)
    assert(c.step(1.3)['Red Soldier reached enemy lines'])
    local choice=assert(ui.upvalue(love.draw,'overlay').choices[action.resurrection])
    failNextWrite=true
    tap(ui.boxCenter(choice))
    assert(not outbound and c.step(0)['Could not send. Tap to retry.'])
    tap(ui.boxCenter(choice))
    tap(ui.boxCenter(choice))
    assert(outbound=='-:'..rules.encode(action) and c.board().moves==0)
    history[#history+1]=outbound:sub(3)
    outbound=nil
  end
  function c.openSetup()
    c.step(4.3)
    local intro=ui.upvalue(love.draw,'intro')
    tap(ui.boxCenter(assert(intro.start)))
    assert(c.step(0)['Match Setup'])
    return ui.upvalue(love.draw,'timers').settings
  end
  function c.tapSetting(key)
    local settings=ui.upvalue(love.draw,'timers').settings
    tap(ui.boxCenter(assert(settings.hits[key],key)))
    return c.step(0)
  end
  function c.start()
    if not ui.upvalue(love.draw,'timers').settings.open then c.openSetup() end
    c.tapSetting('continue')
  end
  function c.reviewOnlineSetup(prompt)
    local view=prompt and ui.upvalue(love.draw,'onlineOpeningPrompt') or ui.upvalue(love.draw,'overlay')
    local back=assert(view.backButton)
    assert(back.x+back.w<view.button.x)
    tap(ui.boxCenter(back))
    c.step(.4)
    local setup=ui.upvalue(love.draw,'timers').settings
    assert(setup.open and setup.review and not setup.hits.picker and setup.hits.continue)
    tap(ui.boxCenter(setup.hits.continue))
    c.step(0)
    assert(not setup.open and not outbound)
  end
  function c.tapOpening()
    local prompt=ui.upvalue(love.draw,'onlineOpeningPrompt')
    tap(ui.boxCenter(assert(prompt.button)))
  end
  function c.takeHostTurn()
    local token=outbound
    outbound=nil
    return token
  end
  function c.continueBattle()
    local overlay = ui.upvalue(love.draw, 'overlay')
    tap(ui.boxCenter(overlay.button))
  end
  return c
end

local red,blue
local function advanceFlow(owner,observer,token)
  local command=assert(owner.takeHostTurn())
  assert(command=='-:'..token,command)
  history[#history+1]=token
  owner.step(.4);observer.step(.4)
end
for _,reward in ipairs({false,true}) do
  match,history,battle=scenario(function(event,after)
    return (event.heal~=nil)==reward and counterattack(after)
  end,reward)
  red,blue=client(1),client(2)
  red.step(.4);blue.step(.4)
  red.submit(battle,true)
  red.step(.4);blue.step(.4)
  blue.step(.4)
  advanceFlow(blue,red,'K')
  red.step(2);blue.step(2)
  local owner=red.step(10)
  local watcher=blue.step(10)
  assert(not watcher.CONTINUE and not watcher['Roll for Reward'])
  if reward then
    assert(owner['Roll for Reward'])
    red.continueBattle()
    advanceFlow(red,blue,'R')
    -- Reopen both clients while the reward handoff is pending.
    red,blue=client(1),client(2)
    red.step(.4);blue.step(.4)
    assert(red.board().last.heal and blue.board().last.heal)
    blue.step(.4)
    advanceFlow(blue,red,'K')
    owner=red.step(6);watcher=blue.step(6)
    assert(not watcher.CONTINUE)
  end
  assert(owner.CONTINUE)
  red.continueBattle()
  advanceFlow(red,blue,'C')
  red.step(2);blue.step(2)
  local reply=assert(counterattack(match))
  blue.submit(reply)
  assert(red.step(.4)['Blue '..rules.classes[match.last.attackerClass].name..' Attacks'])
end
print('PASS: spectators follow attacker reward and continue commands and can take the next turn')

-- Run the host handshake from a blank match, including Blue winning.
for first=1,2 do
  nonce,seed=openingFor(first)
  match=rules.new(seed,first)
  history={}
  red,blue=client(1),client(2)
  local redIntro,blueIntro=red.step(4.4),blue.step(4.4)
  assert(redIntro['Start Game'] and redIntro['You · Red'] and redIntro['Mira Frost · Blue'])
  assert(not blueIntro['Start Game'] and blueIntro['How to Play'] and blueIntro['You · Blue'] and blueIntro['Charles · Red'])
  red.start()
  assert(red.takeHostTurn()=='-:S')
  history[1]='S'
  blue.step(.4)
  assert(blue.takeHostTurn()=='-:K')
  history[2]='K'
  local redRoll,blueWait=red.step(.4),blue.step(.4)
  assert(redRoll['Roll Dice'] and blueWait['Waiting for Charles to roll…'])

  red.step(5);blue.step(5)
  assert(not red.takeHostTurn() and not blue.takeHostTurn(),'setup must wait for inviter')
  red.tapOpening()
  red.step(.4)
  assert(red.takeHostTurn()=='-:I'..nonce[1])
  history[3]='I'..nonce[1]
  blue.step(.4)
  assert(blue.takeHostTurn()=='-:I'..nonce[2])
  history[4]='I'..nonce[2]
  assert(red.step(.4)['Roll to See Who Goes First'])
  assert(blue.step(.4)['Roll to See Who Goes First'])
  red.step(100);blue.step(100)
  red.step(1.1);blue.step(1.1)
  red.step(.4)
  if first==2 then
    assert(red.takeHostTurn()=='-:Y')
    history[5]='Y'
    red.step(.4);blue.step(.4)
  else
    assert(not red.takeHostTurn())
  end
  local openingMove=rules.actions(match)[1]
  local opener=first==1 and red or blue
  opener.submit(openingMove)
  assert(match.moves==1 and match.turn==3-first)
end
print('PASS: online initiative sends setup, supports both first turns and never counts a handoff as a move')

-- Replay a last-Soldier flank attack through two clients, with either kingdom
-- defending, and finish the online handoff before selecting the boulder.
local newBoard=rules.new
for defender=1,2 do
  local attacker=3-defender
  local soldierId=attacker==1 and 12 or 27
  function rules.new(gameSeed,first)
    local board=newBoard(gameSeed,first)
    for _,unit in ipairs(board.units) do unit.hp=0 end
    local fort,soldier=board.forts[defender],board.units[soldierId]
    soldier.hp,soldier.r,soldier.c=16,fort.r,fort.c-1
    return board
  end
  nonce,seed=openingFor(attacker)
  match=rules.new(seed,attacker)
  history={'I'..nonce[1],'I'..nonce[2]}
  if attacker==2 then history[3]='Y' end
  red,blue=client(1),client(2)
  local attackClient,defendClient=attacker==1 and red or blue,defender==1 and red or blue
  red.step(.4);blue.step(.4)
  red.step(100);blue.step(100)
  red.step(2);blue.step(2)
  local fort=match.forts[defender]
  attackClient.submit({type='attack',id=soldierId,r=fort.r,c=fort.c})
  red.step(.4);blue.step(.4)
  defendClient.step(.4)
  advanceFlow(defendClient,attackClient,'K')
  red.step(2);blue.step(2)
  assert(attackClient.step(10).CONTINUE)
  assert(not defendClient.step(10).CONTINUE)
  attackClient.continueBattle()
  advanceFlow(attackClient,defendClient,'C')
  red.step(2);blue.step(2)
  red.step(.4);blue.step(.4)
  assert(not defendClient.takeHostTurn(),'defending client must never send a forced pass')
  local soldier=match.units[soldierId]
  defendClient.submit({type='attack',id=fort.id,r=soldier.r,c=soldier.c})
  red.step(.4);blue.step(.4)
  for _,c in ipairs({red,blue}) do
    local board=c.board()
    assert(board.moves==2 and board.turn==attacker and board.last.attackerClass=='fortress')
    assert(board.forts[defender].armed and board.units[soldierId].hp==soldier.hp)
  end
end
rules.new=newBoard
print('PASS: both online clients agree on the flank attack and Fortress counterattack for either color')

-- Host sets the rules using the actual settings panel and initiative bridge.
-- Blue observes the same wall battle and then triggers a trap on its own turn.
local variants=require('variants')
local originalNew=rules.new
function rules.new(gameSeed,first,options)
  local board=originalNew(gameSeed,first,options)
  board.units[3].r,board.units[3].c=6,1
  return board
end
nonce,seed=openingFor(1)
history={}
red,blue=client(1),client(2)
red.step(4.4);blue.step(4.4)
assert(red.openSetup().open)
red.tapSetting('advanced')
red.tapSetting('crates')
for _=1,3 do red.tapSetting('crateCount1') end
red.tapSetting('wall')
red.tapSetting('destroyCrates')
for _=1,15 do red.tapSetting('wallHealth-1') end
for _=1,3 do red.tapSetting('wallShield-1') end
local wallUI=require('variant_ui')
local drawWall=wallUI.wall
local sections=0
wallUI.wall=function(...)
  sections=sections+1
  return drawWall(...)
end
red.step(0)
assert(sections==rules.rowWidths[6] and not next(red.board().walls))
sections=0
blue.step(0)
assert(sections==0)
wallUI.wall=drawWall
red.start()
local setupPacket=assert(red.takeHostTurn())
assert(setupPacket:match('^%-:S_'))
history[1]=setupPacket:sub(3)
blue.step(.4)
assert(blue.takeHostTurn()=='-:K')
history[2]='K'
red.step(.4)
red.tapOpening()
local optionToken=assert(red.takeHostTurn()):sub(3)
local configured=assert(variants.decode(optionToken:match('^I%d+_(.+)$')))
assert(configured.crates and configured.crateCount==6 and configured.wall and configured.wallHealth==1 and configured.wallShield==0)
assert(configured.destroyCrates and not configured.potions and not configured.traps)
history[3]=optionToken
blue.step(.4)
assert(blue.takeHostTurn()=='-:I'..nonce[2])
history[4]='I'..nonce[2]
red.step(.4);blue.step(.4)
red.step(.4);blue.step(.4)
red.ackBrief();blue.ackBrief()
red.step(100);blue.step(100)
red.step(2);blue.step(2)
match=rules.new(seed,1,configured)
for _,c in ipairs({red,blue}) do
  assert(variants.encode(c.board().options)==variants.encode(configured))
  for key,content in pairs(match.crateContents) do assert(c.board().crateContents[key]==content) end
end
red.submit({type='attack',id=3,r=5,c=1})
red.step(.4);blue.step(.4);blue.step(.4)
advanceFlow(blue,red,'K')
red.step(2);blue.step(2)
assert(red.step(10)['WALL BREACHED'])
assert(blue.step(10)['WALL BREACHED'])
red.continueBattle()
advanceFlow(red,blue,'C')
red.step(2);blue.step(2)
assert(red.board().walls[rules.key(5,1)].hp==0 and blue.board().walls[rules.key(5,1)].hp==0)
local trappedMove
for _,action in ipairs(rules.actions(match)) do
  if action.type=='move' and match.crates[rules.key(action.r,action.c)] then
    trappedMove=action
    break
  end
end
assert(trappedMove,'fixture needs a reachable crate')
blue.submit(trappedMove)
red.step(.4);blue.step(.4)
red.step(2);blue.step(2)
for _,c in ipairs({red,blue}) do
  local title=match.last.crate.contents=='bomb' and 'Bomb Triggered' or 'Health Potion Found'
  local visible=c.step(1.65)
  assert(visible[title])
  assert(not visible['RESOLVING BOOBY TRAP'])
  assert(c.step(2.25)[title],'trap notice must remain readable')
  assert(not c.step(1)[title],'trap notice must clear by itself')
end
assert(red.board().last.crate.change==blue.board().last.crate.change)
assert(red.board().turn==1 and blue.board().turn==1)
red.step(2);blue.step(2)
local destroy
for _,action in ipairs(rules.actions(match)) do
  if action.type=='crate' then destroy=action;break end
end
assert(destroy,'fixture needs a crate in attack range')
red.submit(destroy)
red.step(.4);blue.step(.4)
for _,c in ipairs({red,blue}) do
  local labels=c.step(1.65)
  assert(labels['Mystery Crate Destroyed'])
  assert(labels[match.last.crate.contents=='potion' and 'Health Potion Destroyed' or 'Bomb Detonated'])
  assert(not c.board().crates[rules.key(destroy.r,destroy.c)])
  assert(c.board().scorches[rules.key(destroy.r,destroy.c)])
  assert(c.board().turn==2 and not c.takeHostTurn())
end
rules.new=originalNew
print('PASS: host settings, preshow, wall battle, and synchronized crate opening and destruction')

-- A host rollback during setup must restore Start Game or resend the acknowledgment.
history={}
red,blue=client(1),client(2)
red.openSetup()
red.tapSetting('picker')
red.tapSetting('narrows')
red.start()
local abandoned=assert(red.takeHostTurn()):sub(3)
history[1]=abandoned
red.step(.4);blue.step(.4)
assert(blue.takeHostTurn()=='-:K')
history[2]='K'
red.step(.4);blue.step(.4)
assert(red.board().boardId=='narrows')
history[2]=nil
red.step(.4);blue.step(.4)
assert(blue.takeHostTurn()=='-:K','lost K must be acknowledged again')
history={}
assert(red.step(.4)['Start Game'],'lost Start packet must reopen the lobby')
assert(blue.step(4.4)['How to Play'])
assert(red.board().boardId=='classic' and blue.board().boardId=='classic')
assert(not red.takeHostTurn() and not blue.takeHostTurn())
print('PASS: both clients recover from a missing setup acknowledgment or rolled-back Start packet')

-- Each alternate board survives reconnects before initiative and after a move.
for _,boardId in ipairs({'skirmish','narrows','bridges','wide','corners'}) do
  nonce,seed=openingFor(1)
  history={}
  red,blue=client(1),client(2)
  red.openSetup()
  red.tapSetting('picker')
  red.tapSetting(boardId)
  red.tapSetting('advanced')
  red.tapSetting('crates')
  red.tapSetting('wall')
  red.start()
  history[1]=assert(red.takeHostTurn()):sub(3)
  assert(history[1]:match('^S_B%d+_'))
  if boardId=='bridges' then assert(history[1]:match('^S_B13_')) end
  assert(history[1]:find(boardId=='wide' and '_M' or '_G',1,true))
  blue.step(.4)
  assert(blue.takeHostTurn()=='-:K')
  history[2]='K'
  red=client(1)
  assert(red.step(.4)['Roll Dice'])
  assert(red.board().boardId==boardId and blue.board().boardId==boardId)
  red.reviewOnlineSetup(true)
  red.tapOpening()
  history[3]=assert(red.takeHostTurn()):sub(3)
  assert(history[3]:match('^I%d+_B%d+_'))
  blue.step(.4)
  history[4]=assert(blue.takeHostTurn()):sub(3)
  red.step(.4);blue.step(.4)
  red.step(.4);blue.step(.4)
  red.reviewOnlineSetup(false);blue.reviewOnlineSetup(false)
  red.ackBrief();blue.ackBrief()
  red.step(100);blue.step(100)
  red.step(2);blue.step(2)
  local engine=rules.forBoard(boardId)
  match=red.board()
  assert(match.boardId==boardId and blue.board().boardId==boardId)
  assert(engine.serialize(match)==engine.serialize(blue.board()))
  local move
  for _,action in ipairs(engine.actions(match)) do if action.type=='move' then move=action;break end end
  assert(move)
  history[5]=engine.encode(move)
  local ok=engine.apply(engine.copy(match),move);assert(ok)
  red,blue=client(1),client(2)
  red.step(.4);blue.step(.4)
  assert(red.board().moves==1 and engine.serialize(red.board())==engine.serialize(blue.board()))
end
print('PASS: all five alternate boards synchronize and survive reconnects before the roll and after a move')

-- Recreate the same pre-arrival board on both clients, including after reconnect.
local normalNew=rules.new
function rules.new(gameSeed,first,options)
  local game=normalNew(gameSeed,first,options)
  if game.options.resurrection then
    for _,unit in ipairs(game.units) do unit.hp=0 end
    game.units[12].r,game.units[12].c,game.units[12].hp=1,0,4
    game.units[27].hp=16
  end
  return game
end
nonce,seed=openingFor(1)
local resOptions=variants.defaults()
resOptions.resurrection=true
local encoded=variants.encode(resOptions)
history={'S_'..encoded,'K','I'..nonce[1]..'_'..encoded,'I'..nonce[2]}
red,blue=client(1),client(2)
red.step(.4);blue.step(.4)
red.ackBrief(true);blue.ackBrief(true)
red.step(100);blue.step(100)
red.step(2);blue.step(2)
local promotion={type='move',id=12,r=0,c=0,resurrection=3}
red.chooseResurrection(promotion)
red.step(.4);blue.step(.4)
red.step(1);blue.step(1)
for _,c in ipairs({red,blue}) do
  local board=c.board()
  assert(board.moves==1 and board.turn==2 and board.units[12].class=='wizard',table.concat({board.moves,board.turn,board.units[12].class,tostring(c==red)},','))
  assert(board.units[12].hp==rules.classes.wizard.hp and not c.takeHostTurn())
end
red,blue=client(1),client(2)
red.step(.4);blue.step(.4)
assert(rules.serialize(red.board())==rules.serialize(blue.board()) and red.board().units[12].class=='wizard')
local saved=assert(rules.restore(rules.serialize(red.board())))
assert(saved.units[12].class=='wizard' and saved.units[12].hp==rules.classes.wizard.hp)
rules.new=normalNew
print('PASS: online resurrection stays one turn through a retry, both displays and reconnects')

-- Reopen both clients across the old 512 cutoff and the 4096-entry SDK test target.
paged=true
nonce,seed=openingFor(1)
match=rules.new(seed,1)
history={'S','K','I'..nonce[1],'I'..nonce[2]}
local function shuttle()
  local r=match.turn==1 and 8 or 2
  local edge=match.turn==1 and 7 or 3
  local unit=(rules.occupied(match,r,0) or rules.occupied(match,edge,0)).ref
  return {type='move',id=unit.id,r=unit.r==r and edge or r,c=0}
end
for _,checkpoint in ipairs({512,4096}) do
  while #history<checkpoint do
    local action=shuttle()
    assert(rules.apply(match,action))
    history[#history+1]=rules.encode(action)
  end
  local originalReplay=rules.replay
  local replays=0
  rules.replay=function(...)
    replays=replays+1
    return originalReplay(...)
  end
  red,blue=client(1),client(2)
  for _,c in ipairs({red,blue}) do
    c.step(.4)
    assert(c.board().winner==nil and c.board().moves==checkpoint-4)
  end
  assert(replays==2)
  red.submit(shuttle())
  for _,c in ipairs({red,blue}) do
    c.step(.4)
    c.step(4)
    c.step(2)
    assert(c.board().winner==nil and c.board().moves==checkpoint-3)
    assert(c.board().rng==match.rng)
  end
  blue.submit(shuttle())
  assert(#history==checkpoint+2)
  assert(replays==2,'an ordinary turn after reconnect must not replay the whole match')
  rules.replay=originalReplay
end
print('PASS: paged online games reconnect and continue beyond 512 and 4096 host entries')

-- Replace an already delivered turn without changing the number of messages.
match=rules.new(seed,1)
history={'S','K','I'..nonce[1],'I'..nonce[2]}
local choices=rules.actions(match)
local firstMove,otherMove=choices[1],choices[2]
assert(firstMove.type=='move' and otherMove.type=='move')
local alternate=rules.copy(match)
assert(rules.apply(match,firstMove))
assert(rules.apply(alternate,otherMove))
history[5]=rules.encode(firstMove)
red=client(1)
red.step(.4)
assert(red.board().history[1]==history[5])
history[5]=rules.encode(otherMove)
red.step(.4)
assert(red.board().history[1]==history[5] and red.board().rng==alternate.rng)
history[5]=nil
red.step(.4)
assert(red.board().moves==0 and red.board().first==1)
print('PASS: same-length replacement and shortened history rebuild the live board')

-- The SDK must read all maximum-size tokens without truncating and reject incomplete pages.
local files={mode='online',['match-pages']='2:1:33',['match-revision']='1'}
local pageReads=0
local maxToken=('x'):rep(256)
for page=0,31 do
  files['match-page-'..page]=table.concat({string.rep(maxToken..',',127),maxToken})
end
files['match-page-32']=('y'):rep(256)
local sdk=assert(loadfile('zompa.lua','t',setmetatable({io={open=function(path)
  if path:find('/match-page-',1,true) then pageReads=pageReads+1 end
  local value=files[path:match('^/zompado/(.+)$')]
  return value and {read=function(_,n) return value:sub(1,n) end,close=function() end}
end}},{__index=_G})))()
local list,side,allowed=sdk.readTurns()
assert(#list==4097 and list[4096]==maxToken and list[4097]==files['match-page-32'])
assert(side==2 and allowed)
assert(pageReads==33)
for _=1,10 do
  files['match-pages']='2:0:33'
  list,side,allowed=sdk.readTurns()
  assert(#list==4097 and side==2 and not allowed)
  list[4097]=nil -- A consuming game must not mutate the SDK cache.
end
assert(pageReads==33,'idle polls should not open any history page again')
files['match-revision']='2'
files['match-page-20']=nil
assert(not sdk.readTurns())
print('PASS: SDK accepts 4097 maximum-size tokens and detects a missing page')
