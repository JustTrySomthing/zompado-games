local rules=require('rules')
local variants=require('variants')
local cpu=require('cpu')

local function arrivalFixture(flag,owner)
  local state=rules.new(123,owner,{resurrection=flag})
  for _,unit in ipairs(state.units) do unit.hp=0 end
  local unit=state.units[owner==1 and 12 or 27]
  assert(unit.class=='soldier')
  unit.r,unit.c,unit.hp=owner==1 and 1 or rules.ROWS-2,0,4
  local move={type='move',id=unit.id,r=owner==1 and 0 or rules.ROWS-1,c=0}
  return state,unit,move
end

for owner=1,2 do
 for choice,warrior in ipairs(rules.resurrectionClasses) do
  local state,unit,move=arrivalFixture(true,owner)
  move.resurrection=choice
  local token=rules.encode(move)
  local decoded=assert(rules.decode(token))
  assert(decoded.resurrection==choice)
  local okay,result=rules.apply(state,decoded)
  assert(okay and state.moves==1 and state.turn==3-owner and state.history[1]==token)
  assert(unit.class==warrior and unit.hp==rules.classes[warrior].hp)
  assert(unit.r==move.r and unit.c==move.c and state.units[unit.id]==unit)
  assert(result.resurrection.class==warrior and result.resurrection.soldierHp==4)
 end
end
local field,troop,move=arrivalFixture(false,1)
move.resurrection=3
assert(not rules.apply(field,move) and field.moves==0 and troop.class=='soldier')
assert(not rules.decode('M12_0_0_6') and not rules.decode('A12_0_0_3'))
field,troop,move=arrivalFixture(true,1)
assert(rules.apply(field,move))
assert(troop.class=='soldier' and troop.hp==4)
assert(not rules.resurrectionMove(field,troop,move.r,1),'keeping the Soldier does not offer a second choice on the same row')
field,troop,move=arrivalFixture(true,2)
local selected=assert(cpu(field,function() return 0 end))
assert(selected.resurrection and selected.r==move.r)
assert(rules.apply(field,selected) and troop.class~='soldier')

local corners=rules.forBoard('corners')
local mid=corners.new(123,1,{resurrection=true})
for _,unit in ipairs(mid.units) do unit.hp=0 end
local castaway=mid.units[1]
castaway.class,castaway.r,castaway.c,castaway.hp='soldier',6,4,16
assert(corners.resurrectionSite(mid,1,5,3) and corners.resurrectionSite(mid,1,5,5))
assert(not corners.resurrectionSite(mid,1,0,0) and not corners.resurrectionSite(mid,1,5,2))
assert(corners.apply(mid,{type='move',id=1,r=5,c=5,resurrection=3}))
assert(castaway.class=='wizard')

local legacy=assert(variants.decode('B13_0_3_1_16_3_0_G4_1'))
assert(not legacy.resurrection and variants.encode(legacy)=='B13_0_3_1_16_3_0_G4_1')
for _,board in ipairs(require('boards')) do
 local engine=rules.forBoard(board.id)
 for seed=1,20 do
  for count=1,6 do
   local built=engine.new(seed,1,{resurrection=true,crates=true,crateCount=count,destroyCrates=true,wall=seed%2==0})
   local decoded=assert(variants.decode(variants.encode(built.options)))
   assert(decoded.resurrection and decoded.crates and decoded.crateCount==count)
   local checked=0
   for _,crate in pairs(built.crates) do
    assert(not engine.resurrectionSite(built,1,crate.r,crate.c))
    assert(not engine.resurrectionSite(built,2,crate.r,crate.c))
    checked=checked+1
   end
   assert(checked==count)
   assert(rules.restore(engine.serialize(built)).options.resurrection)
  end
 end
end
print('PASS: resurrection choices, both kingdoms, CPU, Fortress flank fallback, legacy settings, and 720 crate layouts')
