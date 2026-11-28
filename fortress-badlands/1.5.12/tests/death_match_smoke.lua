local rules=require('rules')

local function fixture(seed,rival)
  local state=rules.new(seed,1)
  local attacker=state.units[9]
  local defender=rival=='fortress' and state.forts[2] or state.units[27]
  attacker.r,attacker.c,attacker.hp=5,2,6
  defender.r,defender.c,defender.hp=5,3,rival=='fortress' and 12 or 4
  return state,attacker,defender,{type='attack',id=attacker.id,r=defender.r,c=defender.c}
end

local sawAttackWin,sawDefenseWin,sawTie
for seed=1,160 do
  local state,attacker,defender,action=fixture(seed)
  local attackerHP,defenderHP=attacker.hp,defender.hp
  local online=rules.copy(state)
  local ok,event=rules.apply(state,action)
  assert(ok and event.deathMatch and not event.heal)
  local rounds=event.deathMatch.rounds
  local scores=rounds[#rounds]
  for i,pair in ipairs(rounds) do
    assert(pair[1]>=1 and pair[1]<=12 and pair[2]>=1 and pair[2]<=12)
    if i<#rounds then assert(pair[1]==pair[2]) end
  end
  assert(scores[1]~=scores[2])
  local attackerWon=scores[1]>scores[2]
  assert(event.deathMatch.winner==(attackerWon and 1 or 2))
  assert(attacker.hp==(attackerWon and attackerHP or 0))
  assert(defender.hp==(attackerWon and 0 or defenderHP))
  local token=rules.encode(action,event)
  assert(token:sub(1,1)=='D' and token==state.history[1])
  local synced,replayed=rules.apply(online,assert(rules.decode(token)))
  assert(synced and replayed.deathMatch.winner==event.deathMatch.winner and state.rng==online.rng)
  assert(state.turn==2 and state.moves==1)
  sawAttackWin=sawAttackWin or attackerWon
  sawDefenseWin=sawDefenseWin or not attackerWon
  sawTie=sawTie or #rounds>1
  if sawAttackWin and sawDefenseWin and sawTie then break end
end
assert(sawAttackWin and sawDefenseWin and sawTie)

local state,attacker,defender,action=fixture(1)
local history=rules.encode(action)
local expected=rules.next_random(rules.copy(state),12)
local ok,old=rules.apply(state,rules.decode(history))
assert(ok and not old.deathMatch and old.roll==expected and state.history[1]==history)

state,attacker,defender,action=fixture(1)
attacker.hp=7
local rng=state.rng
assert(not rules.apply(state,rules.decode('D9_5_3')) and state.rng==rng and state.moves==0)
local normalOk,normal=rules.apply(state,action)
assert(normalOk and not normal.deathMatch and normal.roll==expected)

local fortressAttack,fortressDefense
for seed=1,30 do
  state,attacker,defender,action=fixture(seed,'fortress')
  local won,fort=rules.apply(state,action)
  assert(won and fort.deathMatch)
  if fort.defeated then
    assert(state.winner==1 and state.finish=='fortress')
    fortressAttack=true
  else
    assert(state.winner==nil and defender.armed and attacker.hp==0)
    fortressDefense=true
  end
  if fortressAttack and fortressDefense then break end
end
assert(fortressAttack and fortressDefense)
print('PASS: equal D12 duel, rerolls, either side falls, legacy attacks, fortress outcomes, and online replay')
