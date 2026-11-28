local rules=require('rules')
local variants=require('variants')
local choose=require('cpu')
local function size(items)
  local n=0
  for _ in pairs(items) do n=n+1 end
  return n
end

local mixes={}
for seed=1,120 do
  for count=1,9 do
    local options={crates=true,crateCount=count,destroyCrates=seed%2==0,wall=seed%3~=0}
    local board=rules.new(seed,1,options)
    local replay=assert(rules.restore(rules.serialize(board)))
    assert(size(board.crates)==count and size(board.crateContents)==count)
    assert(not next(board.traps) and not next(board.potions) and not next(board.scorches))
    local bombs=0
    for key,crate in pairs(board.crates) do
      assert(not rules.occupied(board,crate.r,crate.c))
      assert(math.abs(crate.r-variants.row)<=(count==9 and 2 or 1))
      for otherKey,other in pairs(board.crates) do
        if otherKey~=key then assert(rules.distance(crate,other)>1,'crates share an edge') end
      end
      assert(replay.crateContents[key]==board.crateContents[key])
      assert(replay.crates[key] and replay.crates[key].c==crate.c)
      assert(crate.contents==nil)
      if board.crateContents[key]=='bomb' then bombs=bombs+1 end
    end
    if count>1 then assert(bombs>=1 and bombs<count,'missing a potion or bomb') end
    mixes[count]=mixes[count] or {}
    mixes[count][bombs]=true
  end
end
assert(size(mixes[1])==2 and size(mixes[3])==2 and size(mixes[9])>=4,'the mix should vary across seeds')
assert(not variants.decode('1_3_1_16_3_0_C6_0'),'legacy traps cannot be enabled alongside crates')
assert(not variants.decode('0_3_0_16_3_0_C0_0'))
assert(variants.decode('1_3_0_16_3_0_2_1').potions,'old options must still decode')

local key=rules.key(5,1)
local function fixture(contents,hp)
  local board=rules.new(81,1,{crates=true,crateCount=1})
  board.crates={[key]={r=5,c=1}}
  board.crateContents={[key]=contents}
  local unit=board.units[3]
  unit.r,unit.c,unit.hp=6,1,hp
  return board,unit
end
for _,contents in ipairs({'potion','bomb'}) do
  local board,unit=fixture(contents,contents=='potion' and 3 or 16)
  local oldHp=unit.hp
  local ok,event=rules.apply(board,{type='move',id=unit.id,r=5,c=1})
  assert(ok and event.crate.contents==contents and not event.crate.destroyed)
  assert(unit.hp==oldHp+(contents=='potion' and 12 or -12))
  assert(board.crates[key]==nil and board.crateContents[key]==nil)
  assert(board.scorches[key]==(contents=='bomb' and true or nil))
  board,unit=fixture(contents,18)
  local shot={type='crate',id=unit.id,r=5,c=1}
  assert(not rules.apply(board,shot),'setting off must reject shots')
  board.options.destroyCrates=true
  ok,event=rules.apply(board,shot)
  assert(ok and event.crate.destroyed and event.crate.contents==contents)
  assert(board.scorches[key] and not board.crates[key] and unit.hp==18)
  assert(rules.decode(board.history[1]).type=='crate')
end
local board,unit=fixture('potion',15)
assert(rules.apply(board,{type='move',id=unit.id,r=5,c=1}))
assert(unit.hp==18 and not board.crates[key],'potion is capped and one-use')
board,unit=fixture('bomb',12)
assert(rules.apply(board,{type='move',id=unit.id,r=5,c=1}))
assert(unit.hp==0 and board.scorches[key])

-- Screenshot position, mirrored for both colors. The crate beside a soldier is
-- a legal attack within reach, and a forward crate is also a legal move.
for player=1,2 do
  for _,destroy in ipairs({false,true}) do
    local board=rules.new(81,player,{wall=true,crates=true,destroyCrates=destroy})
    local row=player==1 and 4 or 6
    local forward=player==1 and 3 or 7
    local soldier=board.units[player==1 and 12 or 27]
    soldier.r,soldier.c,soldier.hp=row,2,3
    for _,enemy in ipairs(board.units) do
      if enemy.r==forward then enemy.hp=0 end
    end
    local sideKey,forwardKey=rules.key(row,1),rules.key(forward,2)
    board.crates={[sideKey]={r=row,c=1},[forwardKey]={r=forward,c=2}}
    board.crateContents={[sideKey]='bomb',[forwardKey]='potion'}
    assert(not rules.moves(board,soldier.id)[sideKey] and rules.moves(board,soldier.id)[forwardKey])
    assert((rules.attacks(board,soldier.id)[sideKey]~=nil)==destroy)
    local nextBoard=rules.copy(board)
    local ok,event=rules.apply(nextBoard,{type='crate',id=soldier.id,r=row,c=1})
    assert(ok==destroy)
    if destroy then
      assert(event.crate.destroyed and event.crate.contents=='bomb' and nextBoard.scorches[sideKey])
      assert(nextBoard.units[soldier.id].hp==3)
    end
    ok,event=rules.apply(board,{type='move',id=soldier.id,r=forward,c=2})
    assert(ok and event.crate.contents=='potion' and soldier.hp==15)
  end
end

-- Preserve the exact crate layout from 1.3.0.
local legacy='OPTIONS:0_3_1_16_3_0_C3_1|v22|81|1|0|0|0|0|'
local saved=assert(rules.restore(legacy))
assert(saved.options.legacyCrates and rules.serialize(saved)==legacy)
assert(size(saved.crates)==3 and saved.crateContents[45]=='bomb'
  and saved.crateContents[46]=='bomb' and saved.crateContents[30]=='potion')
assert(saved.walls[rules.key(5,0)] and saved.walls[rules.key(5,5)])
local played=assert(rules.restore(legacy..'M13_6_3'))
assert(played.last.crate.contents=='bomb' and played.last.crate.change==-12)

for seed=1,32 do
  local board=rules.new(seed,2,{crates=true,crateCount=9,destroyCrates=true,wall=seed%2==0})
  board.units[18].r,board.units[18].c,board.units[18].hp=4,0,6
  local function random()return .25 end
  local action=rules.encode(choose(board,random))
  local function hidden()error('CPU tried to read crate contents')end
  board.crateContents=setmetatable({},{__index=hidden,__pairs=hidden,__len=hidden})
  assert(rules.encode(choose(board,random))==action)
end
print('PASS: max-count generation, fixed effects, adjacent and ranged attacks, scorch, legacy options, and hidden-content fairness')
