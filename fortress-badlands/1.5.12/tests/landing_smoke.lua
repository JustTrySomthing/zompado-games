package.path='./?.lua;'..package.path
local r=require('rules')
local key=r.key
local s=r.new(123)
for _,unit in ipairs(s.units) do unit.hp=0 end
local archer,ally,enemy,far=s.units[4],s.units[1],s.units[16],s.units[17]
archer.hp,archer.r,archer.c=14,4,0
enemy.hp,enemy.r,enemy.c=25,4,3
far.hp,far.r,far.c=25,4,4
assert(r.moves(s,archer.id)[key(4,2)]==2)
assert(not r.moves(s,archer.id)[key(4,3)])
ally.hp,ally.r,ally.c=25,4,1
assert(not r.route(s,archer.id,4,2))
assert(r.attacks(s,archer.id)[key(4,3)])
assert(not r.attacks(s,archer.id)[key(4,4)])
far.r,far.c=5,1
assert(r.distance(archer,far)==2,'fixture is inside Archer range')
assert(not r.attacks(s,archer.id)[key(5,1)],'Archer needs a straight firing line')
local wizard=s.units[3]
wizard.r,wizard.c,wizard.hp=archer.r,archer.c,18
assert(r.inAttackRange(wizard,far),'Wizard can fire off-axis')
wizard.hp=0
assert(r.apply(s,{type='attack',id=archer.id,r=4,c=3}))
assert(archer.r==4 and archer.c==0 and archer.hp==14)
assert(enemy.hp==25 or enemy.hp==19)

local assassin=s.units[8]
assassin.hp,assassin.r,assassin.c=18,6,0
enemy.r,enemy.c=6,5
s.turn=1
assert(r.moves(s,assassin.id)[key(6,4)]==4)
assert(not r.attacks(s,assassin.id)[key(6,5)])
enemy.c=1
assert(r.attacks(s,assassin.id)[key(6,1)] and not r.route(s,assassin.id,6,1))
enemy.c=2
assert(r.attacks(s,assassin.id)[key(6,2)],'Assassin can strike at distance two on a straight line')
enemy.r,enemy.c=5,1
assert(r.distance(assassin,enemy)==2 and not r.attacks(s,assassin.id)[key(5,1)],
  'Assassin cannot bend an attack around a hex')
enemy.r,enemy.c=6,3
assert(not r.attacks(s,assassin.id)[key(6,3)],'Assassin cannot strike at distance three')

for owner=1,2 do
 local fort=s.forts[owner]
 local front=owner==1 and -1 or 1
 local attacker=s.units[owner==1 and 19 or 4]
 attacker.hp,attacker.r,attacker.c=14,fort.r+front*3,1
 local homeGuard=s.units[owner==1 and 2 or 17]
 homeGuard.hp,homeGuard.r,homeGuard.c=25,fort.r+front*2,1
 s.turn=owner
 assert(not next(r.attacks(s,fort.id)) and not next(r.moves(s,fort.id)))
 s.turn=3-owner
 assert(r.apply(s,{type='attack',id=attacker.id,r=fort.r,c=fort.c}))
 assert(fort.armed and s.turn==owner)
 assert(r.attacks(s,fort.id)[key(attacker.r,attacker.c)])
 local farSpot={r=fort.r+front*4,c=2}
 assert(not r.inAttackRange(fort,farSpot) and r.inAttackRange(fort,{r=fort.r,c=0}))
 assert(r.apply(s,{type='attack',id=fort.id,r=attacker.r,c=attacker.c}))
 assert(fort.r==(owner==1 and 10 or 0))
end
print('PASS: separate move and attack ranges, straight Archer and Assassin attacks, off-axis Wizard spells, shots over troops, mirrored Fortress front range')
