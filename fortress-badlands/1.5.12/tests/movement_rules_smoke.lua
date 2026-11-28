package.path='./?.lua;'..package.path
local rules=require('rules')
local function key(r,c) return rules.key(r,c) end
local function clean()
 local s=rules.new(33071)
 for _,u in ipairs(s.units) do u.hp=0 end
 s.turn=1
 return s
end

local s=clean()
local ogre=s.units[7]
ogre.hp=24;ogre.r=5;ogre.c=2
local count=0
for _ in pairs(rules.moves(s,ogre.id)) do count=count+1 end
assert(count==6,'Ogres retain all six directions')

s=clean()
assert(rules.mustPass(s) and rules.actions(s)[1].type=='pass')
local ok,event=rules.apply(s,{type='pass'})
assert(ok and event.siege and s.finish=='siege')
assert(s.winner==1 or s.winner==2)

assert(rules.classes.wizard.hp==18 and rules.FORT_HP==50)

-- Wizard can teleport OVER friends or enemies but not land on an ally.
s=clean()
local wizard=s.units[3] -- first Wizard in the approved back-rank formation
assert(wizard.class=='wizard')
wizard.hp=16;wizard.r=5;wizard.c=2
local blocker=s.units[1];blocker.hp=16;blocker.r=5;blocker.c=3
assert(rules.jumpOver(s,wizard.id,5,4)[key(5,3)],'Teleport cue must include the crossed troop')
assert(rules.moves(s,wizard.id)[key(5,4)],
  'Wizard cannot teleport over an allied piece to an open target')
local teleportRoute=rules.route(s,wizard.id,5,4)
assert(teleportRoute and #teleportRoute==2,
  'Teleport route must skip intermediate occupied hex')
assert(not rules.moves(s,wizard.id)[key(5,3)],
  'Wizard cannot land on an ally')
assert(not rules.moves(s,wizard.id)[key(5,5)],
  'Wizard teleport may not exceed two hexes')
local foe=s.units[16];foe.hp=25;foe.r=5;foe.c=4
assert(rules.attacks(s,wizard.id)[key(5,4)],'Wizard fireballs cross intervening troops')
local far=s.units[17];far.hp,far.r,far.c=25,5,5
assert(not rules.attacks(s,wizard.id)[key(5,5)],'Wizard fireball stops at range two')
assert(not rules.moves(s,wizard.id)[key(5,4)],
  'An occupied hex cannot be a move destination')
assert(not rules.route(s,wizard.id,5,4))
-- Barbarians attack all six adjacent hexes and move up to two hexes.
s=clean()
local barbarian=s.units[1]
assert(barbarian.class=='barbarian')
barbarian.hp,barbarian.r,barbarian.c=25,5,2
for index,pos in ipairs(rules.neighbors(barbarian.r,barbarian.c)) do
  local enemy=s.units[15+index]
  enemy.hp,enemy.r,enemy.c=16,pos.r,pos.c
end
local twoAway=s.units[22]
twoAway.hp,twoAway.r,twoAway.c=24,5,4
local targets=rules.attacks(s,barbarian.id)
for _,pos in ipairs(rules.neighbors(barbarian.r,barbarian.c)) do
  assert(targets[key(pos.r,pos.c)],'Every neighboring enemy is attackable')
end
assert(not targets[key(5,4)] and not rules.apply(s,{type='attack',id=barbarian.id,r=5,c=4}),
  'Barbarian attacks stop at one hex')
assert(rules.apply(s,{type='attack',id=barbarian.id,r=5,c=3}))
assert(barbarian.r==5 and barbarian.c==2,'A Barbarian stays on its hex when it attacks')
for _,u in ipairs(s.units) do if u~=barbarian then u.hp=0 end end
s.turn=1
assert(rules.moves(s,barbarian.id)[key(6,4)],'Barbarian movement still reaches two hexes with a turn')

-- A legal opening-board teleport replays from the original formation.
local opening=rules.new(33071)
assert(rules.moves(opening,3)[key(7,0)],
  'Opening Wizard should teleport over its Archer to empty flank')
local okay,ev=rules.apply(opening,{type='move',id=3,r=7,c=0})
assert(okay,ev)
local restored,err=rules.restore(rules.serialize(opening))
assert(restored,err)
assert(restored.units[3].r==7 and restored.units[3].c==0,
  'teleport must reproduce exactly in local/online replay')
print('PASS: mirrored attacks and forced passes; Wizard two-hex teleport over units; class rules and replay')

local cpu=require('cpu')
for _,def in ipairs(require('boards')) do
 local engine=rules.forBoard(def.id)
 for owner=1,2 do
  local field=engine.new(33071,owner)
  local soldier,ally
  for _,unit in ipairs(field.units) do
   unit.hp=0
   if unit.owner==owner then
    if unit.class=='soldier' then soldier=unit end
    ally=ally or unit
   end
  end
  -- Four Corners has no starting Soldiers, but uses the same movement rule.
  soldier=soldier or ally
  soldier.class,soldier.hp='soldier',16
  local far=owner==1 and 0 or engine.ROWS-1
  local near=owner==1 and 1 or far-1
  local home=engine.ROWS-1-far
  soldier.r,soldier.c=home,0
  assert(not engine.moves(field,soldier.id)[engine.key(home,1)])
  soldier.r=near
  assert(not engine.moves(field,soldier.id)[engine.key(near,1)])
  soldier.r=far
  local destination=engine.key(far,1)
  local lateral=engine.moves(field,soldier.id)
  local fortress=field.forts[3-owner]
  local nextToFort=fortress.r==far and fortress.c==1
  assert((nextToFort or lateral[destination]) and not lateral[engine.key(near,0)])
  assert(not lateral[engine.key(far,2)])
  for _,adjacent in ipairs(engine.neighbors(far,0)) do
   if adjacent.r~=far then assert(not lateral[engine.key(adjacent.r,adjacent.c)]) end
  end
  local picked=assert(cpu(field,function() return 0 end))
  if nextToFort then
   assert(picked.type=='attack' and picked.c==1,'adjacent Fortress can still be attacked from the side')
  elseif def.id~='corners' then
   assert(picked.type=='move' and picked.r==far and picked.c==1,'CPU must use the back row to approach the Fortress')
  end
  local blocker
  for _,unit in ipairs(field.units) do
   if unit.owner~=owner then blocker=unit;break end
  end
  blocker.r,blocker.c,blocker.hp=far,1,16
  assert(not engine.moves(field,soldier.id)[destination])
  assert(engine.attacks(field,soldier.id)[destination],'a sideways attack is still legal')
  blocker.hp=0
  field.replayingForwardOnlySoldiers=true
  assert(not engine.moves(field,soldier.id)[destination])
  field.replayingForwardOnlySoldiers=nil
  if not nextToFort then
   assert(engine.apply(field,{type='move',id=soldier.id,r=far,c=1}))
   assert(soldier.r==far and soldier.c==1)
  end
 end
end
print('PASS: every battlefield allows a one-hex back-row sidestep, preserves blocking, and gives the CPU a route')

