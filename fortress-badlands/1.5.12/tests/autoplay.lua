package.path='./?.lua;'..package.path
local r=require('rules')
math.randomseed(20261123)
local outcomes={fortress=0,siege=0,mutual=0,stalemate=0,limit=0}
local num=24
local totalTurns,unitCaptures,battles,duels=0,0,0,0
for match=1,num do
  local seed=match*991+101
  local s=r.new(seed,r.initiative(seed).first)
  for turn=1,900 do
    if s.winner~=nil then break end
    local acts=r.actions(s)
    assert(#acts>0,'no legal actions')
    local other=s.forts[3-s.turn]
    local best,score
    local bias=(match%3==0 and 23 or 9)
    for _,act in ipairs(acts) do
      local value=-1e9
      if act.type=='pass' then value=0
      elseif act.type=='attack' then
        local target=r.occupied(s,act.r,act.c)
        value=target.kind=='fort' and (29+bias) or 22
        if target.kind=='unit' then
          local u=r.piece(s,act.id)
          local e=target.ref
          value=value+(r.classes[e.class].hp-e.hp)*.5+(u.hp/e.hp)
        end
      elseif act.type=='move' then
        local u=r.piece(s,act.id)
        value=(r.distance(u,other)-r.distance(act,other))*(match%4==0 and 10 or 5)
        value=value+math.random()*2
        if s.last and s.last.type=='move' and s.last.id==act.id and s.last.from and
          act.r==s.last.from.r and act.c==s.last.from.c then value=value-16 end
      end
      if score==nil or value>score then best,score=act,value end
    end
    assert(best,'must choose something')
    local ok,event=r.apply(s,best)
    assert(ok,event)
    if event.type=='attack' then
      battles=battles+1
      if event.defeated or event.attackerDefeated then unitCaptures=unitCaptures+1 end
      if event.deathMatch then
        duels=duels+1
        assert(s.history[#s.history]:sub(1,1)=='D')
        local replayed=assert(r.restore(r.serialize(s)))
        assert(replayed.last.deathMatch.winner==event.deathMatch.winner and replayed.rng==s.rng)
      else
        assert(event.roll>=1 and event.roll<=12)
      end
    end
    if turn%40==0 or s.winner then
    local resumed,err=r.restore(r.serialize(s))
    assert(resumed,err)
    assert(resumed.winner==s.winner,'replay winner')
    assert(resumed.forts[1].hp==s.forts[1].hp and resumed.forts[2].hp==s.forts[2].hp,'replay fortress HP')
    for i,u in ipairs(s.units) do
      assert(u.hp>=0 and u.hp<=r.classes[u.class].hp,'invalid HP')
      assert(resumed.units[i].hp==u.hp,'replay unit HP')
    end
  end
    end
  local outcome=s.finish or 'limit';outcomes[outcome]=outcomes[outcome]+1
  totalTurns=totalTurns+s.moves
end
print(('Autoplay %d matches: fortress=%d final siege=%d mutual=%d stalemate=%d limit=%d mean-turns=%.1f battles=%d defeated=%d death-matches=%d'):format(num,outcomes.fortress,outcomes.siege,outcomes.mutual,outcomes.stalemate,outcomes.limit,totalTurns/num,battles,unitCaptures,duels))
assert(outcomes.limit==0,'All automated games must terminate')
assert(battles>0 and unitCaptures>0,'Expect combat and defeated pieces')
