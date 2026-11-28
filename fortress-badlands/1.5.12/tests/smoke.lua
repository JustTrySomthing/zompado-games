package.path='./?.lua;'..package.path
local r=require('rules')
local function eq(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end
local s=r.new(123)
eq(r.ROWS,11);eq(r.COLS,7)
eq(#s.units,30);eq(r.count(s,1),15);eq(r.count(s,2),15)
local shape={3,4,5,6,7,6,7,6,5,4,3}
local cells=0
for row=0,10 do
 eq(r.rowWidths[row+1],shape[row+1])
 for col=0,6 do
  eq(r.playable(row,col),col<shape[row+1])
  if r.playable(row,col) then cells=cells+1 end
 end
end
eq(cells,56)
local counts={archer=0,soldier=0,wizard=0,assassin=0,barbarian=0,ogre=0}
local occupied={}
for _,u in ipairs(s.units) do
 assert(r.playable(u.r,u.c))
 if u.owner==1 then counts[u.class]=counts[u.class]+1 end
 local id=r.key(u.r,u.c)
 assert(not occupied[u.owner..':'..id],'duplicate starting hex')
 occupied[u.owner..':'..id]=true
 assert(r.occupied(s,u.r,u.c).ref==u)
end
for class,n in pairs({archer=2,soldier=4,wizard=2,assassin=2,barbarian=3,ogre=2}) do
 eq(counts[class],n)
end
for i=1,15 do
 local a,b=s.units[i],s.units[i+15]
 eq(b.r,10-a.r);eq(b.c,a.c);eq(b.class,a.class)
end
eq(s.forts[1].r,10);eq(s.forts[1].c,1)
eq(s.forts[2].r,0);eq(s.forts[2].c,1)
eq(r.occupied(s,10,1).kind,'fort')
eq(r.occupied(s,0,1).kind,'fort')
for _,rear in ipairs({0,10}) do
 local front=rear==0 and 3 or 7
 for _,col in ipairs({0,2}) do eq(r.occupied(s,rear,col).ref.class,'barbarian') end
 for col=1,4 do eq(r.occupied(s,front,col).ref.class,'soldier') end
 eq(r.occupied(s,front,0),nil);eq(r.occupied(s,front,5),nil)
 local second=rear==0 and 1 or 9
 for col=1,2 do eq(r.occupied(s,second,col).ref.class,'archer') end
end
-- Actual adjacent hexes, not the old 8-square crossing moves.
for row=0,10 do for col=0,shape[row+1]-1 do
 local neighbors=r.neighbors(row,col)
 assert(#neighbors>=2 and #neighbors<=6)
 for _,p in ipairs(neighbors) do
  assert(r.playable(p.r,p.c))
  eq(r.distance({r=row,c=col},p),1)
  local reciprocal=false
  for _,q in ipairs(r.neighbors(p.r,p.c)) do
   if q.r==row and q.c==col then reciprocal=true end
  end
  assert(reciprocal,'hex neighbors must be symmetric')
 end
end end
local shields={soldier=2,assassin=3,ogre=5,barbarian=4,fortress=3,wizard=4,archer=3}
local powers={soldier=8,assassin=10,ogre=12,barbarian=11,fortress=8,wizard=10,archer=6}
local health={soldier=16,assassin=18,ogre=24,barbarian=25,fortress=50,wizard=18,archer=14}
for name,stats in pairs(r.classes) do
 eq(stats.shield,shields[name]);eq(stats.power,powers[name]);eq(stats.hp,health[name])
 assert(stats.power>=1 and stats.power<=12 and stats.shield>=1 and stats.shield<=12)
end
local rolls,bonuses={},{}
local equality=false
for seed=1,240 do
 local st=r.new(seed)
 local attacker,defender=st.units[8],st.units[23]
 attacker.r,attacker.c,attacker.hp=4,1,10
 defender.r,defender.c,defender.hp=4,2,10
 local action={type='attack',id=8,r=4,c=2}
 local ok,event=r.apply(st,action);assert(ok,event)
 rolls[event.roll]=true
 eq(st.turn,2);eq(st.moves,1)
 eq(attacker.r,4);eq(attacker.c,1)
 eq(event.landed,event.roll>event.shield)
 if event.landed then
  eq(defender.hp,0);eq(event.damage,10)
  bonuses[event.heal.roll]=true
  eq(attacker.hp,math.min(18,10+event.heal.roll))
 else
  eq(defender.hp,10);eq(attacker.hp,10);eq(event.heal,nil)
  if event.roll==event.shield then equality=true end
 end
end
assert(equality,'Shield ties must repel')
for i=1,12 do assert(rolls[i] and bonuses[i],'both dice must cover all twelve faces') end
local st=r.new(17)
local a=st.units[8];a.r,a.c=4,1
local b=st.units[23];b.r,b.c=4,2;b.hp=18
assert(r.apply(st,{type='attack',id=a.id,r=4,c=2}))
assert(b.hp==18 or b.hp==8)
assert(st.last.heal==nil and a.hp==18)
local clean=r.new(4217)
local acts=r.actions(clean);assert(#acts>0)
assert(r.apply(clean,acts[1]))
local second=r.actions(clean)[1]
assert(r.apply(clean,second))
local third=r.actions(clean)[1]
assert(r.apply(clean,third))
eq(clean.last.actor,1)
eq(clean.previous.actor,2)
eq(clean.previous.id,second.id)
local copy=r.copy(clean)
eq(copy.previous.id,second.id)
assert(copy.previous~=clean.previous,'CPU history should copy independently')
if clean.last.type=='move' then
 eq(clean.last.route[1].r,clean.last.from.r)
 eq(clean.last.route[#clean.last.route].r,clean.last.to.r)
end
local saved=r.serialize(clean)
assert(saved:sub(1,4)=='v22|')
for _,malformed in ipairs({saved..',', (saved:gsub(',',',,',1)), (saved:gsub('|([MAD])','|,%1',1))}) do
 local restored,err=r.restore(malformed)
 assert(restored==nil and err=='Invalid save history.')
end
local restored,err=r.restore(saved);assert(restored,err)
eq(restored.previous.actor,2);eq(restored.previous.id,second.id)
for i,u in ipairs(clean.units) do
 eq(restored.units[i].hp,u.hp);eq(restored.units[i].r,u.r);eq(restored.units[i].c,u.c)
end
assert(not r.decode('M31_1_3'))
assert(not r.restore('v16|'..saved:sub(5)),'older stats must not affect new match replay')
assert(not r.restore('v5|123|'),'incompatible old-layout saved games must not load')
assert(not r.restore('v6|'..saved:sub(5)),'must not replay v0.5.0 saves under changed movement and combat rules')
assert(not r.restore('v7|'..saved:sub(5)),'must not replay old actions against the new starting formation')
assert(not r.restore('v8|'..saved:sub(5)),'old rules must not replay against the test movement')
assert(not r.restore('v11|'..saved:sub(5)),'old Archer layout cannot replay against corrected formation')
print('PASS: 56 playable fitted hexes, 30 mirrored units, 2 forts, 6 neighbors, D12 combat and v22 saves')

local starts,ties={0,0},0
for seed=1,1200 do
 local opening=r.initiative(seed)
 local final=opening.rounds[#opening.rounds]
 eq(opening.first,final[1]>final[2] and 1 or 2)
 assert(final[1]~=final[2])
 for i,roll in ipairs(opening.rounds) do
  assert(roll[1]>=1 and roll[1]<=12 and roll[2]>=1 and roll[2]<=12)
  if i<#opening.rounds then eq(roll[1],roll[2]);ties=ties+1 end
 end
 starts[opening.first]=starts[opening.first]+1
end
assert(starts[1]>500 and starts[2]>500 and ties>50)
local blueStart=r.new(123,2)
assert(r.apply(blueStart,r.actions(blueStart)[1]))
local blueRestored=assert(r.restore(r.serialize(blueStart)))
eq(blueRestored.first,2);eq(blueRestored.turn,1)
eq(assert(r.restore('v17|123|')).turn,1)
local legacy='v18|123|1|M6_7_5,M21_3_5,M6_5_4,M21_5_5,M6_3_5,A20_3_5'
local migrated=assert(r.restore(legacy))
eq(migrated.last.roll,10)
eq(migrated.last.defenderHpEnd,12)
assert(not r.replay(migrated.seed,migrated.history,migrated.first),
  'new matches must reject the old off-axis shot')
assert(r.apply(migrated,r.actions(migrated)[1]))
local continued=assert(r.restore(r.serialize(migrated)))
eq(continued.moves,7)
eq(continued.rng,migrated.rng)
local damagedFort='v19|9|1|0|M6_7_5,M30_4_4,M6_5_4,M25_6_6,M6_3_4,M27_4_2,M6_2_3,M23_6_0,A6_0_1'
local upgraded=assert(r.restore(damagedFort))
eq(upgraded.forts[1].hp,50)
eq(upgraded.forts[2].hp,40)
assert(upgraded.forts[2].armed)
assert(r.apply(upgraded,r.actions(upgraded)[1]))
local reloaded=assert(r.restore(r.serialize(upgraded)))
eq(reloaded.forts[2].hp,upgraded.forts[2].hp)
eq(reloaded.rng,upgraded.rng)

-- The v0.5.40 history ends in an off-axis Barbarian strike and a retaliatory roll of 5.
local oldBarbarian='v20|25|1|0|0|M3_7_0,M18_3_0,M6_7_5,M21_3_5,M1_9_0,M16_1_0,M2_9_3,M17_1_3,'
  ..'M3_6_0,M18_4_2,M6_6_4,M21_4_6,M7_7_0,M22_3_0,M1_8_0,M16_2_0,M11_7_5,M26_3_5,'
  ..'M2_8_4,M18_6_3,A9_6_3'
local mixed=assert(r.restore(oldBarbarian))
eq(mixed.last.roll,8)
eq(mixed.last.defenderHpEnd,7)
assert(not r.replay(mixed.seed,mixed.history,mixed.first), 'the old strike is off-axis')
local allOld=assert(r.restore(oldBarbarian..',A18_8_2'))
eq(allOld.last.roll,5)
eq(allOld.last.shield,5)
eq(allOld.units[9].hp,25)
assert(r.apply(mixed,{type='attack',id=18,r=8,c=2}))
eq(mixed.last.roll,5)
eq(mixed.last.shield,4)
eq(mixed.units[9].hp,15)
eq(assert(r.restore(r.serialize(mixed))).units[9].hp,15)
eq(assert(r.restore(r.serialize(allOld))).units[9].hp,25)

local twoHexHistory=oldBarbarian:match('^v20|25|1|0|0|(.-),M18_6_3,A9_6_3$')
local straightSave='v21|25|1|0|0|0|'..twoHexHistory..',M18_6_2'
local straight=assert(r.restore(straightSave..',A9_6_2'))
eq(straight.last.roll,8)
eq(straight.last.defenderHpEnd,7)
eq(assert(r.restore(r.serialize(straight))).last.defenderHpEnd,7)
assert(not r.restore('v21|25|1|0|0|0|'..twoHexHistory..',M18_6_3,A9_6_3'))
local nextTurn=assert(r.restore(straightSave))
assert(not r.apply(nextTurn,{type='attack',id=9,r=6,c=2}),
  'Only played turns use the historical two-hex range')

local siegeTies=0
for seed=1,64 do
 local field=r.new(seed)
 for _,unit in ipairs(field.units) do unit.hp=0 end
 field.forts[1].hp,field.forts[2].hp=9,50
 local ok,event=r.apply(field,{type='pass'})
 assert(ok and event.siege and event.winner==field.winner)
 local hp=event.siege.start
 assert(hp[1]==9 and hp[2]==50)
 for index,volley in ipairs(event.siege.volleys) do
  assert(volley.a>=1 and volley.a<=12 and volley.b>=1 and volley.b<=12)
  if volley.a==volley.b then
   siegeTies=siegeTies+1
   eq(volley.hit,0);eq(volley.hp[1],hp[1]);eq(volley.hp[2],hp[2])
  else
   local winner=volley.a>volley.b and 1 or 2
   eq(volley.hit,winner);eq(volley.hp[winner],hp[winner])
   eq(volley.hp[3-winner],math.max(0,hp[3-winner]-r.classes.fortress.power))
  end
  hp=volley.hp
  if index<#event.siege.volleys then assert(hp[1]>0 and hp[2]>0) end
 end
 assert(hp[field.winner]>0 and hp[3-field.winner]==0)
end
assert(siegeTies>0)

local decisiveTies,redWins,blueWins=0,0,0
for seed=1,64 do
 local field=r.new(seed)
 for _,unit in ipairs(field.units) do unit.hp=0 end
 field.forts[1].hp,field.forts[2].hp=9,12
 local ok,event=r.apply(field,{type='pass'})
 assert(ok and event.siege.deathMatch)
 assert(r.serialize(field):match('^v23|'))
 local last=#event.siege.volleys
 for index,volley in ipairs(event.siege.volleys) do
  if index<last then
   eq(volley.hit,0);eq(volley.hp[1],9);eq(volley.hp[2],12)
   decisiveTies=decisiveTies+1
  else
   local winner=field.winner
   assert(volley.a~=volley.b)
   eq(volley.hit,winner);eq(volley.hp[winner],event.siege.start[winner]);eq(volley.hp[3-winner],0)
   if winner==1 then redWins=redWins+1 else blueWins=blueWins+1 end
  end
 end
end
assert(decisiveTies>0 and redWins>0 and blueWins>0)

for _,legacy in ipairs({false,true}) do
 local field=r.new(1)
 for _,unit in ipairs(field.units) do unit.hp=0 end
 field.forts[1].hp,field.forts[2].hp=12,legacy and 12 or 13
 field.replayingLegacySiege=legacy
 local ok,event=r.apply(field,{type='pass'})
 assert(ok and not event.siege.deathMatch and #event.siege.volleys>=2)
 assert(r.serialize(field):match('^v22|'))
end
print('PASS: Final Siege Death Match triggers only for two critical Fortresses, rerolls ties and preserves older conclusions')

-- Killing the last troop with a Fortress leads into the siege immediately.
local endgame=r.new(1)
for _,unit in ipairs(endgame.units) do unit.hp=0 end
local attacker=endgame.forts[1]
attacker.armed=true
local target=endgame.units[17]
target.r,target.c,target.hp=8,1,2
for seed=1,20 do
 local trial=r.copy(endgame)
 trial.rng=seed
 local ok,event=r.apply(trial,{type='attack',id=attacker.id,r=target.r,c=target.c})
 assert(ok)
 if event.defeated then
  assert(event.siege and event.finish=='siege' and event.winner~=0)
  endgame=nil
  break
 end
end
assert(not endgame)
print('PASS: initiative ties reroll, both sides can open, and Final Siege resolves a single winner')

local full=r.new(1)
local archer,foe=full.units[4],full.units[23]
archer.r,archer.c=4,0
foe.r,foe.c,foe.hp=4,3,1
local oldRng=r.copy(full)
r.next_random(oldRng,12)
r.next_random(oldRng,12)
local ok,win=r.apply(full,{type='attack',id=archer.id,r=4,c=3})
assert(ok and win.defeated and win.fullHealth and not win.heal)
assert(archer.hp==14 and full.rng==oldRng.rng)
print('PASS: full-Health victories skip the bonus die and preserve the save replay sequence')
