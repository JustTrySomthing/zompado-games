local rules=require('rules')
local choose=require('cpu')
local state=rules.new(1,2)
for _,unit in ipairs(state.units) do unit.hp=0 end
local wizard=state.units[18]
local left,right,front=state.units[3],state.units[6],state.units[12]
local function put(unit,hp,r,c)
  unit.hp,unit.r,unit.c=hp,r,c
end
local function pick()
  local rng=state.rng
  local action=choose(state,function() return 0 end)
  assert(state.rng==rng and state.moves==0,'CPU must not preview the actual dice rolls')
  return assert(action)
end

put(wizard,2,5,2)
put(left,18,6,1)
put(right,18,6,3)
put(front,16,6,2)
local retreat=pick()
assert(retreat.type=='move' and retreat.id==wizard.id,'wounded Wizard should retreat')
for _,enemy in ipairs({left,right,front}) do
  assert(rules.inAttackRange(enemy,wizard),'fixture must threaten the Wizard')
  assert(not rules.inAttackRange(enemy,retreat),'retreat must clear the enemies’ strike ranges')
end
assert(rules.apply(rules.copy(state),retreat),'retreat must respect Wizard movement rules')

-- One opponent can be finished, and any repositioning leaves nearby ranged threats.
-- The wounded Wizard can gamble on putting the Archer out and healing from the kill.
left=state.units[4]
state.units[3].hp=0
put(left,2,5,0)
put(right,18,5,3)
wizard.hp=5
local attack=pick()
assert(attack.type=='attack' and attack.id==wizard.id and attack.r==left.r and attack.c==left.c,
  'CPU should take an available finishing strike when the reward can justify exposure')
assert(rules.apply(rules.copy(state),attack),'attack must respect Wizard strike range')
print('PASS: wounded CPU retreats from overlapping threats and weighs a finishing attack against its healing reward')

-- A tempting attack across the board must not distract the CPU from its Fortress.
state=rules.new(123,2)
for _,unit in ipairs(state.units) do unit.hp=0 end
put(state.units[18],18,3,2)
put(state.units[22],24,9,0)
put(state.units[3],18,1,0)
put(state.units[4],14,1,1)
put(state.units[12],16,1,2)
local defense=pick()
assert(defense.type=='attack' and defense.id==18 and defense.r==1,
  'the CPU should use a defender when three enemies threaten its Fortress')
state.units[18].r=4
defense=pick()
assert(defense.type=='move' and defense.id==18,
  'the CPU should reposition a defender before committing elsewhere')
assert(rules.inAttackRange({class='wizard',r=defense.r,c=defense.c},state.units[12]),
  'the defender should cover a troop threatening the Fortress')
state.units[18].r=3
state.units[4].hp,state.units[12].hp=0,0
state.forts[2].armed=true
state.last={type='attack',actor=1,defenderClass='fortress'}
defense=pick()
assert(defense.type=='attack' and defense.r==1 and defense.c==0,
  'the CPU must respond to a direct Fortress attack even from a single enemy')
print('PASS: CPU intercepts coordinated threats, repositions defenders, and responds after a Fortress attack')

state=rules.new(31,2)
for _,unit in ipairs(state.units) do unit.hp=0 end
local barbarian,ogre,soldier=state.units[24],state.units[7],state.units[12]
put(barbarian,25,5,2)
put(ogre,10,6,3)
assert(rules.distance(barbarian,ogre)==1)
local strike=pick()
assert(strike.type=='attack' and strike.id==barbarian.id and strike.r==ogre.r and strike.c==ogre.c,
  'a healthy Barbarian should attack an adjacent enemy')
assert(rules.apply(rules.copy(state),strike))

ogre.hp=0
put(soldier,6,6,4)
assert(rules.distance(barbarian,soldier)==2 and not rules.inAttackRange(barbarian,soldier))
local approach=pick()
assert(approach.type=='move' and approach.id==barbarian.id and rules.distance(approach,soldier)==1,
  'a Barbarian should close to melee range to set up a finishing attack')
assert(rules.apply(rules.copy(state),approach))

soldier.hp=0
put(barbarian,2,5,2)
put(ogre,24,6,3)
local archer,redWizard=state.units[4],state.units[3]
put(archer,14,5,0)
put(redWizard,18,6,1)
local safeMove=pick()
assert(safeMove.type=='move' and safeMove.id==barbarian.id and not rules.inAttackRange(ogre,safeMove)
  and not rules.inAttackRange(archer,safeMove) and not rules.inAttackRange(redWizard,safeMove),
  'a critical Barbarian should retreat from overlapping threats even with an adjacent strike available')
assert(rules.apply(rules.copy(state),safeMove))
print('PASS: Barbarians attack adjacent enemies, close to melee range, and retreat from overlapping threats')

local function advanced(options)
  local board=rules.new(1,2,options)
  for _,unit in ipairs(board.units) do unit.hp=0 end
  return board
end
local function placePotion(board,r,c,heal)
  board.potions={[rules.key(r,c)]={r=r,c=c,heal=heal}}
end

state=advanced({potions=true})
put(state.units[24],3,4,1)
placePotion(state,5,1,5)
assert(rules.encode(pick())=='M24_5_1','wounded CPU should take an accessible potion')

state=advanced({potions=true,destroyPotions=true})
put(state.units[19],14,3,2)
put(state.units[12],2,6,3)
placePotion(state,5,3,5)
assert(rules.encode(pick())=='X19_5_3','destroy a potion a wounded opponent can claim')
state.units[12].r,state.units[12].c=5,4
local redTurn=setmetatable({turn=1},{__index=state})
assert(rules.distance(state.units[12],state.potions[rules.key(5,3)])==1
  and not rules.moves(redTurn,12)[rules.key(5,3)],'nearby Soldier can only advance forward')
assert(pick().type~='potion','avoid spending a turn denying a potion only near a wounded enemy')
state.options.destroyPotions=false
assert(pick().type~='potion','indestructible potion remains unavailable to the CPU')

state=advanced({wall=true,wallHealth=6,wallShield=0})
put(state.units[18],18,4,0)
put(state.units[27],16,3,0)
local attackable=rules.attacks(state,18)
assert(attackable[rules.key(5,0)] and attackable[rules.key(5,1)])
assert(rules.encode(pick())=='A18_5_0','favor the reachable flank crossing over an adjacent section')

state=advanced({wall=true,wallHealth=6,wallShield=0})
put(state.units[18],18,4,2)
put(state.units[12],3,6,3)
local breach=pick()
assert(breach.type=='attack' and breach.r==5,'closed wall should block the finishing shot')
state.options.overWall=true
assert(rules.encode(pick())=='A18_6_3','take a finishing ranged shot when the setting allows it')

state=advanced({traps=true,trapCount=9})
put(state.units[24],3,3,2)
assert(pick().r<4,'critically wounded troop should prefer a safe approach to a heavily trapped zone')
state.triggeredTraps=9
assert(pick().r>=4,'public knowledge that traps have gone off should remove that penalty')

local function hiddenRead()
  error('CPU read hidden setup information')
end
for seed=1,36 do
  local board=rules.new(seed,2,{traps=true,wall=seed%2==0,potions=true,
    potionCount=3,destroyPotions=seed%3~=0})
  if board.options.wall then board.walls[rules.key(5,0)].hp=0 end
  board.units[16].hp=2
  board.units[1].hp=4
  local expected=rules.encode(choose(board,function() return .4 end))
  local visible=rules.copy(board)
  visible.traps=setmetatable({},{__index=hiddenRead,__pairs=hiddenRead,__len=hiddenRead})
  visible.rng,visible.seed=nil,nil
  for _,potion in pairs(visible.potions) do
    potion.heal=nil
    setmetatable(potion,{__index=hiddenRead})
  end
  setmetatable(visible,{__index=function(_,key)
    if key=='seed' or key=='rng' then return hiddenRead() end
  end})
  assert(rules.encode(choose(visible,function() return .4 end))==expected,
    'identical visible states must produce identical CPU choices')
end
print('PASS: CPU uses legal potion access, useful breaches, ranged options and public trap risk without reading hidden data')

-- Three open flank sections should end the wizard-only wall bombardment.
-- The opposing side stays near its starting ranks so there is a reason to advance.
state=rules.new(51,2,{wall=true,wallHealth=16,wallShield=3})
for _,column in ipairs({0,4,5}) do state.walls[rules.key(5,column)].hp=0 end
state.units[18].r,state.units[18].c=4,3
local crossed,reinforced=false,false
for turn=1,36 do
  local action
  if state.turn==2 then
    action=choose(state,function() return 0 end)
    local piece=rules.piece(state,action.id)
    if action.type=='move' then
      if piece.r<=5 and action.r>5 then crossed=true end
      if piece.class~='wizard' and action.r>piece.r and action.r>=4 then reinforced=true end
    end
    if turn<=7 then
      assert(not (action.type=='attack' and action.r==5),'use the available flank instead of shooting more wall')
    end
  else
    for _,candidate in ipairs(rules.actions(state)) do
      if candidate.type=='move' and (not action or candidate.r>action.r) then action=candidate end
    end
  end
  assert(action and rules.apply(state,action))
end
assert(crossed and reinforced,'CPU should cross via a gap and move non-Wizard troops up behind it')
print('PASS: existing flank gaps break the wall-attack loop and bring up reinforcements')
