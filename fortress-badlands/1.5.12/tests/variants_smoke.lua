local rules=require('rules')
local variants=require('variants')
local ui=require('variant_ui')
local choose=require('cpu')
local function count(values)
  local n=0
  for _ in pairs(values) do n=n+1 end
  return n
end
local seed=1
local options=variants.defaults()
assert(not options.traps and not options.wall and options.trapCount==3)
assert(variants.encode(variants.decode(variants.encode(options)))==variants.encode(options))
assert(not variants.decode('1_0_1_10_3_0') and not variants.decode('1_3_1_0_3_0')
  and not variants.decode('1_3_1_10_12_0'))
local baseline=rules.new(seed)
assert(count(baseline.walls)==0 and count(baseline.traps)==0)
for _,size in ipairs({1,3,9}) do
  options.traps,options.trapCount,options.wall=true,size,true
  local a,b=rules.new(seed,1,options),rules.new(seed,1,options)
  assert(a.rng==baseline.rng and count(a.traps)==size)
  for key,damage in pairs(a.traps) do
    local row=rules.fromkey(key)
    assert(damage>=1 and damage<=12 and row>=4 and row<=6)
    assert(a.walls[key]==nil and b.traps[key]==damage)
  end
  assert(count(a.walls)==rules.rowWidths[6])
end

local state=rules.new(seed,1,options)
local wizard=state.units[3]
wizard.r,wizard.c=6,1
local blue=state.units[18]
blue.r,blue.c=4,2
assert(not rules.attacks(state,wizard.id)[rules.key(blue.r,blue.c)])
assert(not rules.route(state,wizard.id,4,0), 'teleport cannot bypass an intact wall')
state.options.overWall=true
assert(rules.attacks(state,wizard.id)[rules.key(blue.r,blue.c)])
assert(not rules.route(state,wizard.id,4,0), 'ranged-fire option must not allow teleport through a wall')
state.options.overWall=false
local action={type='attack',id=wizard.id,r=5,c=1}
local section=state.walls[rules.key(5,1)]
local adjacent=state.walls[rules.key(5,2)]
assert(rules.attacks(state,wizard.id)[rules.key(5,1)].kind=='wall')
local ok,first=rules.apply(state,action)
assert(ok and first.wallHealth==16 and first.shield==3 and first.damage==10)
assert(not first.defeated and section.hp==6 and adjacent.hp==16)
state.turn=1
local _,second=rules.apply(state,action)
assert(second.defeated and section.hp==0 and adjacent.hp==16)
assert(not second.heal and not second.fullHealth and not second.deathMatch)
assert(not rules.occupied(state,5,1),'a destroyed wall section opens the tile')
state.turn=1
assert(rules.route(state,wizard.id,5,1))
assert(rules.attacks(state,wizard.id)[rules.key(blue.r,blue.c)],'a shot passes through the gap')
section.hp=16
state.rng=2
local _,blocked=rules.apply(state,action)
assert(blocked.roll==3 and blocked.damage==0 and section.hp==16,'the roll must be above Shield')

-- Movement traverses intermediate hexes without triggering their traps.
local field=rules.new(seed,1,{traps=true,trapCount=3})
field.traps={}
for _,u in ipairs(field.units) do u.hp=0 end
local ogre=field.units[7]
ogre.hp,ogre.r,ogre.c=24,6,1
local traveler=field.units[1]
traveler.hp,traveler.r,traveler.c=25,6,2
local path=assert(rules.route(field,traveler.id,4,2))
assert(#path==3)
local intermediate=rules.key(path[2].r,path[2].c)
field.traps[intermediate]=12
field.traps[rules.key(4,2)]=7
local _,land=rules.apply(field,{type='move',id=traveler.id,r=4,c=2})
assert(land.trap.damage==7 and traveler.hp==18 and not field.traps[rules.key(4,2)])
assert(field.traps[intermediate]==12 and field.turn==2)
field.turn=1
field.traps[rules.key(5,1)]=12
ogre.hp=4
local _,lethal=rules.apply(field,{type='move',id=ogre.id,r=5,c=1})
assert(lethal.trap.damage==4 and lethal.trap.remaining==0 and ogre.hp==0)

-- Full games with both variants, using production CPU decisions, then replay
-- the entire saved histories to verify deterministic wear, traps and outcomes.
math.randomseed(95713)
local wallAttacks,triggered,potionEvents=0,0,0
options.potions,options.potionCount,options.destroyPotions=true,3,true
for i=1,4 do
  options.overWall=i%2==0
  local game=rules.new(1723*i,1,options)
  for _=1,600 do
    if game.winner~=nil then break end
    local selected=assert(choose(game,math.random))
    local valid,event=rules.apply(game,selected)
    assert(valid,event)
    if event.wallHealth then wallAttacks=wallAttacks+1 end
    if event.trap then triggered=triggered+1 end
    if event.potion then potionEvents=potionEvents+1 end
  end
  assert(game.winner~=nil,'variant game must end')
  local replay=assert(rules.restore(rules.serialize(game)))
  assert(replay.rng==game.rng and replay.winner==game.winner and replay.moves==game.moves)
  assert(rules.serialize(replay)==rules.serialize(game))
  for key,wall in pairs(game.walls) do assert(replay.walls[key].hp==wall.hp) end
  assert(count(replay.traps)==count(game.traps) and count(replay.potions)==count(game.potions))
end
assert(wallAttacks>0 and triggered>0 and potionEvents>0)

local graphics={}
for _,fn in ipairs({'setColor','rectangle','circle','line','setFont','printf','setLineWidth','push','pop','scale'}) do
  graphics[fn]=function() end
end
local fonts={medium={},small={},stat={},cardHint={}}
for _,viewport in ipairs({{w=158,h=212,viewportH=236},{w=212,h=276,viewportH=300},{w=390,h=670,viewportH=700}}) do
  local setup={options=variants.defaults()}
  local function draw()
    setup.hits=ui.drawSetup(graphics,viewport,fonts,setup,function() end,function() end)
    for _,control in pairs(setup.hits) do
      assert(control.x>=0 and control.y>=0 and control.x+control.w<=viewport.w and control.y+control.h<=viewport.h)
    end
  end
  local function tap(key)
    local b=assert(setup.hits[key],key)
    local action=ui.tapSetup(setup,b.x+b.w*.5,b.y+b.h*.5)
    draw()
    return action
  end
  draw()
  assert(not setup.hits.wall and not setup.hits.crates)
  tap('picker')
  assert(not setup.hits.continue)
  tap('skirmish')
  assert(setup.options.board=='skirmish' and setup.options.crateCount==2)
  tap('advanced')
  assert(not setup.hits.crateCount1 and not setup.hits.wallHealth1 and not setup.hits.overWall)
  local picker,advanced=setup.hits.picker,setup.hits.advanced
  assert(picker.y+picker.h<=advanced.y)
  tap('crates')
  for _=1,4 do tap('crateCount1') end
  assert(setup.options.crateCount==6 and not setup.hits.crateCount1)
  for _=1,5 do tap('crateCount-1') end
  assert(setup.options.crateCount==1 and not setup.hits['crateCount-1'])
  tap('wall')
  tap('overWall')
  assert(setup.options.wall and setup.options.overWall)
  assert(setup.hits.back.x<setup.hits.continue.x and tap('back')=='back' and tap('continue')=='continue')
end
print('PASS: optional rules, deterministic traps, wall damage and line of fire, four complete CPU games and settings touch controls')

-- The new option preserves the old trap sequence and all maximum counts.
for seed=1,80 do
  local old=rules.new(seed,1,{wall=true,traps=true,trapCount=9})
  local newer=rules.new(seed,1,{wall=true,traps=true,trapCount=9,potions=true,potionCount=3,destroyPotions=true})
  assert(count(newer.potions)==3 and count(newer.traps)==9)
  for key,damage in pairs(old.traps) do assert(newer.traps[key]==damage) end
  for key,potion in pairs(newer.potions) do
    assert(not newer.walls[key] and not newer.traps[key])
    assert(potion.heal>=3 and potion.heal<=8)
  end
  assert(variants.encode(variants.decode(variants.encode(newer.options)))==variants.encode(newer.options))
  assert(not variants.decode(variants.encode(old.options)).potions)
end

local bottle=rules.new(46,1,{potions=true,potionCount=1})
for _,u in ipairs(bottle.units) do u.hp=0 end
bottle.potions={[rules.key(5,2)]={r=5,c=2,heal=7}}
local wizard=bottle.units[3]
wizard.r,wizard.c,wizard.hp=6,2,18
local destroy={type='potion',id=wizard.id,r=5,c=2}
local collect={type='move',id=wizard.id,r=5,c=2}
assert(not rules.apply(bottle,destroy) and rules.route(bottle,wizard.id,5,2))
local trial=rules.copy(bottle)
assert(rules.apply(trial,collect) and trial.potions[rules.key(5,2)],'full-health unit leaves the potion')
trial=rules.copy(bottle)
trial.units[3].hp=15
local ok,recovery=rules.apply(trial,collect)
assert(ok and recovery.potion.gained==3 and trial.units[3].hp==18 and not next(trial.potions))
bottle.options.destroyPotions=true
local savedRng=bottle.rng
local hit,shatter=rules.apply(bottle,destroy)
assert(hit and shatter.potion.class=='wizard' and not shatter.potion.gained)
assert(not next(bottle.potions) and bottle.turn==2 and bottle.moves==1 and bottle.rng==savedRng)
assert(rules.decode(bottle.history[1]).type=='potion')
print('PASS: 80 combined placements, potion pickup cap, optional one-hit destruction and replay encoding')
