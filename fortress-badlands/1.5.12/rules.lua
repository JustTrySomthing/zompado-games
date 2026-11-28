-- Zompa Fortress Strategy: pure deterministic rules (no LÖVE dependencies).
-- Board positions are zero-based (row 0..10, column 0..6); row widths vary.
local boards=require('boards')
local variants=require('variants')
local engines={}
local function forBoard(id)
  return assert(engines[id or 'classic'],'Unknown battlefield')
end
local function create(board)
  local M = {board=board,forBoard=forBoard,ROWS=#board.rows,COLS=board.columns,rowWidths=board.rows}

  M.classes = {
    soldier   = {hp=16, move=1, forward=true, power=8,  shield=2, name='Soldier', mark='S'},
    wizard    = {hp=18, move=2, range=2, projectile=true, power=10,  shield=4, name='Wizard', mark='W'},
    assassin  = {hp=18, straight=true, range=2, attackStraight=true, power=10, shield=3, name='Assassin', mark='A'},
    archer    = {hp=14, move=2, straight=true, range=3, attackStraight=true, projectile=true, power=6, shield=3, name='Archer', mark='R'},
    barbarian = {hp=25, move=2, range=1, power=11, shield=4, name='Barbarian', mark='B'},
    ogre      = {hp=24, move=1, power=12, shield=5, name='Ogre', mark='O'},
    fortress  = {hp=50, move=0, range=3, projectile=true, power=8, shield=3, name='Fortress'},
  }
  M.FORT_HP, M.DIE = M.classes.fortress.hp, 12
  -- True tessellated hex footprint. Each row is indexed left to right, so
  -- neighboring row centers shift by half of one horizontal hex pitch.
  function M.playable(r,c)
    return type(r)=='number' and type(c)=='number' and r%1==0 and c%1==0
      and r>=0 and r<M.ROWS and c>=0 and c<M.rowWidths[r+1] 
      and (not board.crossings or r~=board.middle or board.crossings[c])
      and (not board.gaps or not board.gaps[r] or not board.gaps[r][c])
  end
  local on=M.playable
  function M.key(r,c) return r*M.COLS+c end
  function M.fromkey(k) return math.floor(k/M.COLS), k%M.COLS end
  -- Axial coordinates allow exact hex distance/adjacency despite row widths.
  local function axial(r,c)
    return c+(M.COLS-M.rowWidths[r+1]-r)/2,r
  end
  local function column(q,r)
    return q-(M.COLS-M.rowWidths[r+1]-r)/2
  end
  local directions={{1,0},{-1,0},{0,1},{-1,1},{0,-1},{1,-1}}
  local function hexDelta(a,b)
    local aq,ar=axial(a.r,a.c)
    local bq,br=axial(b.r,b.c)
    local dq,dr=bq-aq,br-ar
    return dq,dr,math.max(math.abs(dq),math.abs(dr),math.abs(dq+dr))
  end
  function M.distance(a,b)
    local _,_,distance=hexDelta(a,b)
    return distance
  end
  function M.neighbors(r,c)
    local out={}
    if not on(r,c) then return out end
    local q,rr=axial(r,c)
    for _,d in ipairs(directions) do
      local nr=rr+d[2]
      if nr>=0 and nr<M.ROWS then
        local nc=column(q+d[1],nr)
        if on(nr,nc) then out[#out+1]={r=nr,c=nc} end
      end
    end
    return out
  end
  -- Wizards can jump troops, but a gap needs a connected route in range.
  local function connectedReach(s,a,b)
    local hasGap=board.gaps or board.crossings or board.id=='narrows-legacy' and not s.replayingNarrows150
    if not hasGap or M.distance(a,b)==1 then return true end
    for _,step in ipairs(M.neighbors(a.r,a.c)) do
      if M.distance(step,b)==1 then return true end
    end
    return false
  end
  function M.line(a,b)
    -- Display-only shortest geometric line for future line-of-sight features.
    -- Captures use the actual obstacle-aware BFS route, not this line.
    local n=M.distance(a,b);local out={}
    if n==0 then return {{r=a.r,c=a.c}} end
    for i=0,n do
      local t=i/n
      out[#out+1]={r=math.floor(a.r+(b.r-a.r)*t+.5),c=math.floor(a.c+(b.c-a.c)*t+.5)}
    end
    return out
  end

  -- Approved 11-row hourglass board: 56 joined hexagons and 15 troops
  -- plus the two-tower fortress per kingdom. Top and bottom mirror exactly.
  -- Red is bottom (rows 7-10), Blue is top (rows 0-3).
  local formation = {
    -- Rearmost row: Barbarian / Fortress / Barbarian.
    {r=10,c=0,class='barbarian'}, {r=10,c=2,class='barbarian'},
    -- Four-hex rank: Wizard / Archer / Archer / Wizard.
    {r=9,c=0,class='wizard'}, {r=9,c=1,class='archer'},
    {r=9,c=2,class='archer'}, {r=9,c=3,class='wizard'},
    -- Five-hex rank: Ogre / Assassin / Barbarian / Assassin / Ogre.
    {r=8,c=0,class='ogre'}, {r=8,c=1,class='assassin'},
    {r=8,c=2,class='barbarian'}, {r=8,c=3,class='assassin'},
    {r=8,c=4,class='ogre'},
    -- Front rank: four Soldiers, with both flanks open.
    {r=7,c=1,class='soldier'}, {r=7,c=2,class='soldier'},
    {r=7,c=3,class='soldier'}, {r=7,c=4,class='soldier'},
  }
  local redKeep,blueKeep=1,1
  local classes={S='soldier',W='wizard',R='archer',A='assassin',B='barbarian',O='ogre'}
  local teamFormations
  if board.formation then
    teamFormations={}
    for owner,rows in ipairs(board.formation) do
      local pieces={troops={}}
      for row,line in ipairs(rows) do
        assert(#line==board.rows[row])
        for index=1,#line do
          local mark=line:sub(index,index)
          if mark~='.' then
            local r,c=row-1,index-1
            assert(on(r,c))
            if mark=='F' then pieces.keep={r=r,c=c}
            else pieces.troops[#pieces.troops+1]={r=r,c=c,class=assert(classes[mark])} end
          end
        end
      end
      teamFormations[owner]=pieces
    end
    formation=teamFormations[1].troops
    assert(#formation==#teamFormations[2].troops)
  elseif board.blue then
    formation={}
    for row,line in ipairs(board.blue) do
      assert(#line==board.rows[row])
      for index=1,#line do
        local mark=line:sub(index,index)
        local c=board.rows[row]-index
        if mark=='F' then redKeep,blueKeep=c,index-1
        elseif mark~='.' then
          formation[#formation+1]={r=M.ROWS-row,c=c,class=assert(classes[mark])}
        end
      end
    end
  end
  M.formation=formation

  local function advance_rng(s)
    s.rng=(s.rng*48271)%2147483647
  end
  local function next_random(s,n)
    advance_rng(s)
    return 1+(s.rng%n)
  end
  M.next_random=next_random
  function M.initiative(seed)
    local rng={rng=(seed*40699+73)%2147483646+1}
    local opening={rounds={}}
    repeat
      local red,blue=next_random(rng,M.DIE),next_random(rng,M.DIE)
      opening.rounds[#opening.rounds+1]={red,blue}
      if red~=blue then opening.first=red>blue and 1 or 2 end
    until opening.first
    return opening
  end
  function M.new(seed,first,options)
    if options and options.board and options.board~=board.id then
      return forBoard(options.board).new(seed,first,options)
    end
    seed=math.floor(tonumber(seed) or 1489967)%2147483647
    if seed<1 then seed=1 end
    local s={version=22,boardId=board.id,seed=seed,rng=seed,first=first or 1,turn=first or 1,moves=0,units={},
      forts={{r=M.ROWS-1,c=redKeep,hp=M.FORT_HP,owner=1,id=2*#formation+1,class='fortress'},{r=0,c=blueKeep,hp=M.FORT_HP,owner=2,id=2*#formation+2,class='fortress'}},
      winner=nil,finish=nil,history={},last=nil}
    for player=1,2 do
      local pieces=teamFormations and teamFormations[player]
      if pieces then
        s.forts[player].r,s.forts[player].c=pieces.keep.r,pieces.keep.c
      end
      for _,p in ipairs(pieces and pieces.troops or formation) do
        local r=player==1 and p.r or (M.ROWS-1-p.r)
        local c=player==2 and board.blue and M.rowWidths[r+1]-1-p.c or p.c
        if pieces then r,c=p.r,p.c end
        s.units[#s.units+1]={id=#s.units+1,owner=player,r=r,c=c,
          class=p.class,hp=M.classes[p.class].hp}
      end
    end
    variants.setup(s,M,options)
    return s
  end
  function M.copy(s)
    local d={}
    for k,v in pairs(s) do
      if type(v)~='table' then d[k]=v end
    end
    local function copy(t)
      local n={};for k,v in pairs(t) do n[k]=type(v)=='table' and copy(v) or v end;return n
    end
    for _,name in ipairs({'units','forts','history','last','previous','options','traps','walls','potions','crates','crateContents','scorches'}) do
      if s[name] then d[name]=copy(s[name]) end
    end
    return d
  end
  function M.count(s,owner)
    local n=0;for _,u in ipairs(s.units) do if u.owner==owner and u.hp>0 then n=n+1 end end
    return n
  end
  function M.occupied(s,r,c)
    local wall=s.walls[M.key(r,c)]
    if wall and wall.hp>0 then return {kind='wall',ref=wall,owner=0} end
    for _,f in ipairs(s.forts) do if f.r==r and f.c==c then return {kind='fort',ref=f,owner=f.owner} end end
    for _,u in ipairs(s.units) do if u.hp>0 and u.r==r and u.c==c then return {kind='unit',ref=u,owner=u.owner} end end
  end
  function M.piece(s,id)
    if type(id)~="number" then return nil end
    return s.units[id] or s.forts[id-2*#formation]
  end

  M.resurrectionClasses={'barbarian','ogre','wizard','archer','assassin'}

  function M.resurrectionSite(s,owner,r,c)
    if not on(r,c) then return false end
    local enemy=s.forts[3-owner]
    local backRow=owner==1 and 0 or M.ROWS-1
    if enemy.r==backRow then return r==backRow end
    return r==enemy.r and math.abs(c-enemy.c)==1
  end

  function M.resurrectionMove(s,unit,r,c)
    return s.options.resurrection and unit and unit.class=='soldier'
      and M.resurrectionSite(s,unit.owner,r,c) and not M.resurrectionSite(s,unit.owner,unit.r,unit.c)
  end

  function M.soldierMoveRow(row,owner)
    local backRow=owner==1 and 0 or M.ROWS-1
    if row==backRow then return row end
    return row+(owner==1 and -1 or 1)
  end

  -- Movement ends on an empty hex. Wizard teleport may cross occupied hexes.
  local function destinations(s,id)
    local u=s.units[id]
    if not u or u.hp<=0 or u.owner~=s.turn or s.winner then return {},{} end
    local class=M.classes[u.class]
    local steps=class.move
    local empty,parents={},{}
    local origin=M.key(u.r,u.c)
    local function mark(r,c,dist,parent)
      if M.occupied(s,r,c) then return false end
      local k=M.key(r,c)
      parents[k],empty[k]=parent,dist
      return true
    end

    if class.forward then
      local moveRow=M.soldierMoveRow(u.r,u.owner)
      if s.replayingForwardOnlySoldiers and moveRow==u.r then return empty,parents end
      for _,target in ipairs(M.neighbors(u.r,u.c)) do
        if target.r==moveRow then mark(target.r,target.c,1,origin) end
      end
      return empty,parents
    end

    if class.straight then
      local q0,r0=axial(u.r,u.c)
      for _,direction in ipairs(directions) do
        local parent=origin
        local q,r=q0,r0
        local distance=0
        while not steps or distance<steps do
          q,r=q+direction[1],r+direction[2]
          if r<0 or r>=M.ROWS then break end
          local c=column(q,r)
          distance=distance+1
          if not on(r,c) then break end
          if not mark(r,c,distance,parent) then break end
          parent=M.key(r,c)
        end
      end
      return empty,parents
    end

    if u.class=='wizard' then
      for r=0,M.ROWS-1 do
        for c=0,M.rowWidths[r+1]-1 do
          local dist=M.distance(u,{r=r,c=c})
          if dist>0 and dist<=steps and on(r,c) and connectedReach(s,u,{r=r,c=c}) and not variants.blocked(s,u,{r=r,c=c},M) then
            mark(r,c,dist,origin)
          end
        end
      end
      return empty,parents
    end

    local seen={[origin]=true}
    local queue={{r=u.r,c=u.c,dist=0}}
    local head=1
    while queue[head] do
      local cur=queue[head];head=head+1
      if cur.dist<steps then
        for _,p in ipairs(M.neighbors(cur.r,cur.c)) do
          local k=M.key(p.r,p.c)
          if not seen[k] then
            seen[k]=true
            local clear=mark(p.r,p.c,cur.dist+1,M.key(cur.r,cur.c))
            if clear then queue[#queue+1]={r=p.r,c=p.c,dist=cur.dist+1} end
          end
        end
      end
    end
    return empty,parents
  end
  function M.route(s,id,r,c)
    if not on(r,c) then return nil end
    local empty,parents=destinations(s,id)
    local target=M.key(r,c)
    if not empty[target] then return nil end
    local u=s.units[id]
    local origin=M.key(u.r,u.c)
    local reversed={};local k=target
    while k do
      local row,col=M.fromkey(k)
      reversed[#reversed+1]={r=row,c=col}
      if k==origin then break end
      k=parents[k]
      if not k then return nil end
    end
    if k~=origin then return nil end
    local out={}
    for i=#reversed,1,-1 do out[#out+1]=reversed[i] end
    return out
  end
  -- A two-step Wizard teleport can cross a shared hex edge.
  function M.jumpOver(s,id,r,c)
    local u=s.units[id]
    local crossed={}
    if u.class=='wizard' and M.distance(u,{r=r,c=c})==2 then
      for _,cell in ipairs(M.neighbors(u.r,u.c)) do
        local occupant=M.occupied(s,cell.r,cell.c)
        if occupant and occupant.kind=='unit' and M.distance(cell,{r=r,c=c})==1 then
          crossed[M.key(cell.r,cell.c)]=true
        end
      end
    end
    return crossed
  end
  function M.isCritical(hp,maximum)
    return hp>0 and hp<=maximum*.25
  end
  function M.isDeathMatch(attacker,defender)
    return M.isCritical(attacker.hp,M.classes[attacker.class].hp)
      and M.isCritical(defender.hp,M.classes[defender.class].hp)
  end
  function M.attackRange(class)
    return M.classes[class].range or 1
  end
  -- Attack range is independent of movement and never changes the attacker's hex.
  function M.inAttackRange(u,target,legacy,barbarianReplay,forwardOnlyFortress)
    local dq,dr,distance=hexDelta(u,target)
    local straight=dq==0 or dr==0 or dq+dr==0
    if u.class=='barbarian' and barbarianReplay then
      return distance>0 and distance<=2 and (barbarianReplay=='wide' or straight)
    end
    local range=legacy and u.class=='assassin' and 1 or M.attackRange(u.class)
    if distance==0 or distance>range then return false end
    if u.class=='fortress' then
      local forward=dr*(u.owner==1 and -1 or 1)>0
      return u.armed and (forward or (not forwardOnlyFortress and dr==0 and distance==1))
    end
    return legacy==true or not M.classes[u.class].attackStraight or straight
  end
  function M.canAttack(s,u,target,forwardOnlyFortress)
    return (M.classes[u.class].projectile or connectedReach(s,u,target))
      and M.inAttackRange(u,target,s.replayingLegacyAttacks,s.replayingBarbarianRules,forwardOnlyFortress)
      and (s.options.overWall and M.classes[u.class].projectile or not variants.blocked(s,u,target,M))
  end
  function M.moves(s,id)
    local empty=destinations(s,id)
    return empty
  end
  function M.attacks(s,id,forwardOnlyFortress)
    local u=M.piece(s,id)
    local targets={}
    if not u or u.hp<=0 or u.owner~=s.turn or s.winner then return targets end
    local function add(target,kind)
      if target.owner~=u.owner and target.hp>0
        and M.canAttack(s,u,target,forwardOnlyFortress) then
        targets[M.key(target.r,target.c)]={ref=target,owner=target.owner,kind=kind}
      end
    end
    for _,enemy in ipairs(s.units) do add(enemy,'unit') end
    for _,fort in ipairs(s.forts) do add(fort,'fort') end
    for _,wall in pairs(s.walls) do add(wall,'wall') end
    if s.options.destroyCrates and (not s.options.legacyCrates or M.classes[u.class].projectile) then
      for key,crate in pairs(s.crates) do
        if not M.occupied(s,crate.r,crate.c) and M.canAttack(s,u,crate,forwardOnlyFortress) then
          targets[key]={ref=crate,kind='crate'}
        end
      end
    end
    if s.options.destroyPotions then
      for key,potion in pairs(s.potions) do
        if not M.occupied(s,potion.r,potion.c) and M.canAttack(s,u,potion,forwardOnlyFortress) then
          targets[key]={ref=potion,kind='potion'}
        end
      end
    end
    return targets
  end
  function M.describeAttack(s,act)
    if not on(act.r,act.c) then return nil end
    local target=M.attacks(s,act.id)[M.key(act.r,act.c)]
    if not target or target.kind=='potion' or target.kind=='crate' then return nil end
    local u,v=M.piece(s,act.id),target.ref
    local shield=v.shield or s.replayingBarbarianRules=='wide' and v.class=='barbarian' and 5 or M.classes[v.class].shield
    return {type='attack',actor=u.owner,id=u.id,
      from={r=u.r,c=u.c},to={r=v.r,c=v.c},
      attackerClass=u.class,defenderClass=v.class,
      attackerHpStart=u.hp,defenderHpStart=v.hp,shield=shield,
      wallHealth=v.class=='wall' and s.options.wallHealth or nil},v
  end
  function M.actions(s,forwardOnlyFortress)
    if s.winner then return {} end
    local actions={}
    for id=1,2*#formation+2 do
      for k in pairs(M.moves(s,id)) do
        local r,c=M.fromkey(k)
        actions[#actions+1]={type='move',id=id,r=r,c=c}
      end
      for k,target in pairs(M.attacks(s,id,forwardOnlyFortress)) do
        local r,c=M.fromkey(k)
        actions[#actions+1]={type=target.kind=='potion' and 'potion' or target.kind=='crate' and 'crate' or 'attack',id=id,r=r,c=c}
      end
    end
    if #actions==0 then return {{type='pass'}} end
    table.sort(actions,function(a,b)
      if a.id~=b.id then return a.id<b.id end
      if a.type~=b.type then return a.type<b.type end
      if a.r~=b.r then return a.r<b.r end
      return a.c<b.c
    end)
    return actions
  end
  function M.mustPass(s,forwardOnlyFortress)
    return not s.winner and M.actions(s,forwardOnlyFortress)[1].type=='pass'
  end
  -- Both Fortress rolls are committed atomically with the last troop defeat.
  -- Playback consumes these volleys without taking extra host turns.
  local function finalSiege(s)
    local red,blue=s.forts[1],s.forts[2]
    local siege={start={red.hp,blue.hp},volleys={}}
    siege.deathMatch=not s.replayingLegacySiege and M.isDeathMatch(red,blue)
    local power=M.classes.fortress.power
    while red.hp>0 and blue.hp>0 do
      local a,b=next_random(s,M.DIE),next_random(s,M.DIE)
      local hit=a>b and 1 or b>a and 2 or 0
      if hit>0 then
        local loser=s.forts[3-hit]
        loser.hp=siege.deathMatch and 0 or math.max(0,loser.hp-power)
      end
      siege.volleys[#siege.volleys+1]={a=a,b=b,hit=hit,hp={red.hp,blue.hp}}
    end
    s.winner=red.hp>0 and 1 or 2
    s.finish='siege'
    return siege
  end
  local function resolveCrate(s,key,unit,destroyed)
    local contents=s.crateContents[key]
    s.crates[key],s.crateContents[key]=nil,nil
    local result={contents=contents,class=unit.class,destroyed=destroyed}
    if destroyed or contents=='bomb' then s.scorches[key]=true end
    if not destroyed then
      local hp=unit.hp
      if contents=='bomb' then unit.hp=math.max(0,hp-variants.crateHealth)
      else unit.hp=math.min(M.classes[unit.class].hp,hp+variants.crateHealth) end
      result.change=unit.hp-hp
      result.remaining=unit.hp
    end
    return result
  end

  function M.apply(s,act,allowSavedFortressPass)
    if s.winner then return false,'Game already ended.' end
    if type(act)~='table' then return false,'Missing action.' end
    if act.resurrection and (act.type~='move' or not M.resurrectionClasses[act.resurrection]) then
      return false,'Invalid resurrection choice.'
    end
    local player=s.turn
    local event={actor=player,type=act.type}
    if act.type=='pass' then
      -- A local save from before flank shots can contain a formerly mandatory pass.
      if not M.mustPass(s,allowSavedFortressPass) then
        return false,'A legal action is available.'
      end
      if s.last and s.last.type=='pass' then s.winner,s.finish=0,'stalemate' end
    elseif act.type=='move' then
      local route=M.route(s,act.id,act.r,act.c)
      if not route then return false,'Blocked or out-of-range movement.' end
      event.route=route
      local u=M.piece(s,act.id)
      if act.resurrection and not M.resurrectionMove(s,u,act.r,act.c) then
        return false,'Resurrection is only available on arrival.'
      end
      event.id=u.id;event.from={r=u.r,c=u.c};event.to={r=act.r,c=act.c}
      u.r,u.c=act.r,act.c
      local key=M.key(act.r,act.c)
      local trap=s.traps[key]
      if s.crates[key] then
        event.crate=resolveCrate(s,key,u,false)
      elseif trap then
        s.traps[key]=nil
        s.triggeredTraps=(s.triggeredTraps or 0)+1
        local damage=math.min(u.hp,trap)
        u.hp=u.hp-damage
        event.trap={roll=trap,damage=damage,remaining=u.hp,class=u.class}
      else
        local potion=s.potions[key]
        local missing=M.classes[u.class].hp-u.hp
        if potion and missing>0 then
          local gained=math.min(missing,potion.heal)
          s.potions[key]=nil
          u.hp=u.hp+gained
          event.potion={class=u.class,gained=gained}
        end
      end
      if act.resurrection and u.hp>0 then
        event.resurrection={class=M.resurrectionClasses[act.resurrection],soldierHp=u.hp}
        u.class=event.resurrection.class
        u.hp=M.classes[u.class].hp
      end
    elseif act.type=='crate' then
      if not on(act.r,act.c) then return false,'Invalid crate hex.' end
      local key=M.key(act.r,act.c)
      local target=M.attacks(s,act.id)[key]
      if not target or target.kind~='crate' then return false,'Crate cannot be attacked.' end
      local u=M.piece(s,act.id)
      event.id,event.to=u.id,{r=act.r,c=act.c}
      event.crate=resolveCrate(s,key,u,true)
    elseif act.type=='potion' then
      if not on(act.r,act.c) then return false,'Invalid potion hex.' end
      local key=M.key(act.r,act.c)
      local target=M.attacks(s,act.id)[key]
      if not target or target.kind~='potion' then return false,'Potion cannot be attacked.' end
      local u=M.piece(s,act.id)
      event.id,event.to=u.id,{r=act.r,c=act.c}
      event.potion={class=u.class}
      s.potions[key]=nil
    elseif act.type=='attack' then
      local defender
      event,defender=M.describeAttack(s,act)
      if not event then return false,'Target outside attack range.' end
      local attacker=M.piece(s,act.id)
      local eligible=defender.class~='wall' and M.isDeathMatch(attacker,defender)
      if act.deathMatch and not eligible then return false,'Both combatants must be critical.' end
      s.battleCount=(s.battleCount or 0)+1
      if defender.class=='fortress' then defender.armed=true end
      if eligible and act.deathMatch~=false then
        local duel={rounds={}}
        repeat
          local a,b=next_random(s,M.DIE),next_random(s,M.DIE)
          duel.rounds[#duel.rounds+1]={a,b}
          if a~=b then duel.winner=a>b and 1 or 2 end
        until duel.winner
        local loser=duel.winner==1 and defender or attacker
        event.deathMatch=duel
        event.landed=loser==defender
        event.damage=event.landed and defender.hp or 0
        loser.hp=0
        event.defeated=loser==defender
        event.attackerDefeated=loser==attacker
        event.attackerHpEnd,event.defenderHpEnd=attacker.hp,defender.hp
        if loser.class=='fortress' then s.winner,s.finish=3-loser.owner,'fortress' end
      else
        local stats=M.classes[attacker.class]
        event.roll=next_random(s,M.DIE)
        event.landed=event.roll>event.shield
        event.damage=event.landed and math.min(defender.hp,stats.power) or 0
        defender.hp=defender.hp-event.damage
        if event.landed and defender.class=='fortress' and not defender.tookHit then
          defender.tookHit=true
          event.firstFortHit=true
        end
        event.defenderHpEnd=defender.hp
        event.defeated=defender.hp==0
        if event.defeated and defender.class~='wall' then
          local maximum=attacker.class=='fortress' and s.legacyFortMax or stats.hp
          if attacker.hp==maximum then
            event.fullHealth=true
            -- Reserve the same RNG step as previous builds so existing saves replay.
            advance_rng(s)
          else
            local bonus=next_random(s,M.DIE)
            local actual=math.min(bonus,maximum-attacker.hp)
            attacker.hp=attacker.hp+actual
            event.heal={roll=bonus,actual=actual}
          end
          if defender.class=='fortress' then s.winner,s.finish=player,'fortress' end
        end
      end
    else
      return false,'Unknown action.'
    end
    if not s.winner and (act.type=='attack' and (event.defeated or event.attackerDefeated) or act.type=='pass' or event.trap and event.trap.remaining==0 or event.crate and event.crate.remaining==0)
      and M.count(s,1)==0 and M.count(s,2)==0 then
      event.siege=finalSiege(s)
    end
    s.history[#s.history+1]=M.encode(act,event)
    s.moves=s.moves+1
    event.winner,event.finish=s.winner,s.finish
    s.previous,s.last=s.last,event
    s.turn=3-player
    return true,event
  end
  function M.encode(a,event)
    if a.type=='pass' then return 'P' end
    local kind=a.type=='move' and 'M' or a.type=='potion' and 'X' or a.type=='crate' and 'T' or ((a.deathMatch or event and event.deathMatch) and 'D' or 'A')
    local token=('%s%d_%d_%d'):format(kind,a.id,a.r,a.c)
    return a.resurrection and token..'_'..a.resurrection or token
  end
  function M.decode(token)
    if token=='P' then return {type='pass'} end
    if type(token)~='string' then return nil end
    local kind,id,r,c=token:match('^([MADXT])(%d+)_(%d+)_(%d+)$')
    local choice
    if not kind then kind,id,r,c,choice=token:match('^(M)(%d+)_(%d+)_(%d+)_([1-5])$') end
    id,r,c=tonumber(id),tonumber(r),tonumber(c)
    if not id or id<1 or id>2*#formation+2 or (kind=='M' and id>2*#formation) or not on(r,c) then return nil end
    local action={type=kind=='M' and 'move' or kind=='X' and 'potion' or kind=='T' and 'crate' or 'attack',id=id,r=r,c=c,resurrection=tonumber(choice)}
    -- Legacy attack tokens preserve their original combat and RNG during replay.
    if kind=='A' or kind=='D' then action.deathMatch=kind=='D' end
    return action
  end
  function M.replay(seed,history,first,legacyCount,legacyFortCount,legacyBarbarianCount,twoHexBarbarianCount,allowSavedFortressPass,options,allowSavedNarrowsMoves,savedVersion)
    if options and options.board and options.board~=board.id then
      return forBoard(options.board).replay(seed,history,first,legacyCount,legacyFortCount,
        legacyBarbarianCount,twoHexBarbarianCount,allowSavedFortressPass,options,allowSavedNarrowsMoves,savedVersion)
    end
    local s=M.new(seed,first,options)
    s.legacyAttackCount=legacyCount
    s.legacyFortCount=legacyFortCount
    s.legacyBarbarianCount=legacyBarbarianCount
    s.twoHexBarbarianCount=twoHexBarbarianCount
    if legacyFortCount and legacyFortCount>0 then
      s.legacyFortMax=30
      for _,fort in ipairs(s.forts) do fort.hp=s.legacyFortMax end
    end
    -- Old local turns keep the combat rules under which they were played.
    -- New turns and all online matches use this build's rules.
    s.replayingLegacySiege=savedVersion and savedVersion~='23'
    for i,token in ipairs(history) do
      local action=M.decode(token)
      if not action then return nil,'Malformed token at move '..i end
      s.replayingLegacyAttacks=legacyCount and i<=legacyCount
      s.replayingBarbarianRules=legacyBarbarianCount and i<=legacyBarbarianCount and 'wide'
        or twoHexBarbarianCount and i<=twoHexBarbarianCount and 'straight' or nil
      local ok,err=M.apply(s,action,allowSavedFortressPass)
      if not ok and savedVersion and action.type=='pass' then
        -- An old mandatory pass can now have a legal sideways move.
        s.replayingForwardOnlySoldiers=true
        ok,err=M.apply(s,action,allowSavedFortressPass)
      end
      if not ok and allowSavedNarrowsMoves then
        -- Prior local saves may contain a gap-crossing action or a pass forced by the old wall bounds.
        -- Validate those actions under 1.5.0 rules only during playback.
        s.replayingNarrows150=true
        ok,err=M.apply(s,action,allowSavedFortressPass)
        s.replayingNarrows150=nil
      end
      s.replayingForwardOnlySoldiers=nil
      if not ok then return nil,'Illegal move '..i..': '..err end
      if i==legacyFortCount then
        for _,fort in ipairs(s.forts) do
          if fort.hp>0 then fort.hp=fort.hp+M.FORT_HP-s.legacyFortMax end
        end
        s.legacyFortMax=nil
      end
    end
    s.replayingLegacyAttacks,s.replayingBarbarianRules,s.replayingLegacySiege=nil,nil,nil
    return s
  end
  function M.serialize(s)
    local prefix=variants.enabled(s.options) and ('OPTIONS:'..variants.encode(s.options)..'|') or ''
    local version=s.last and s.last.siege and s.last.siege.deathMatch and 'v23' or 'v22'
    return prefix..version..('|%d|%d|%d|%d|%d|%d|%s'):format(s.seed,s.first,s.legacyAttackCount or 0,
      s.legacyFortCount or 0,s.legacyBarbarianCount or 0,s.twoHexBarbarianCount or 0,
      table.concat(s.history,','))
  end
  function M.restore(data)
    if type(data)~='string' or #data>262144 then return nil,'Invalid save.' end
    local options
    if data:sub(1,8)=='OPTIONS:' then
      local encoded,body=data:match('^OPTIONS:([^|]+)|(.+)$')
      if not encoded then return nil,'Invalid match options.' end
      options=variants.decode(encoded)
      if not options then return nil,'Invalid match options.' end
      data=body
    end
    local saveVersion,seed,first,legacyCount,legacyFortCount,legacyBarbarianCount,twoHexBarbarianCount,str=
      data:match('^v(2[23])|(%d+)|([12])|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$')
    if not seed then
      seed,first,legacyCount,legacyFortCount,legacyBarbarianCount,str=
        data:match('^v21|(%d+)|([12])|(%d+)|(%d+)|(%d+)|(.*)$')
    end
    if not seed then
      seed,first,legacyCount,legacyFortCount,str=data:match('^v20|(%d+)|([12])|(%d+)|(%d+)|(.*)$')
    end
    if not seed then seed,first,legacyCount,str=data:match('^v19|(%d+)|([12])|(%d+)|(.*)$') end
    if not seed then
      seed,first,str=data:match('^v18|(%d+)|([12])|(.*)$')
      if not seed then seed,str=data:match('^v17|(%d+)|(.*)$') end
    end
    if not seed or #seed>12 then return nil,'Unrecognized save version.' end
    if str:sub(1,1)==',' or str:sub(-1)==',' or str:find(',,',1,true) then
      return nil,'Invalid save history.'
    end
    local tokens={}
    for t in str:gmatch('[^,]+') do tokens[#tokens+1]=t end
    local oldTurns=legacyCount and tonumber(legacyCount) or #tokens
    local oldFortTurns=legacyFortCount and tonumber(legacyFortCount) or #tokens
    local oldBarbarianTurns=legacyBarbarianCount and tonumber(legacyBarbarianCount) or #tokens
    local oldTwoHexTurns=twoHexBarbarianCount and tonumber(twoHexBarbarianCount) or #tokens
    if oldTurns>oldFortTurns or oldFortTurns>oldBarbarianTurns or oldBarbarianTurns>oldTwoHexTurns
      or oldTwoHexTurns>#tokens then
      return nil,'Invalid saved turn count.'
    end
    return M.replay(tonumber(seed),tokens,tonumber(first),oldTurns,oldFortTurns,oldBarbarianTurns,oldTwoHexTurns,not options,options,options and options.board=='narrows-legacy',saveVersion or '22')
  end
  return M
end

for _,board in ipairs(boards) do engines[board.id]=create(board) end
engines['narrows-legacy']=create(boards['narrows-legacy'])
engines['corners-legacy']=create(boards['corners-legacy'])
engines['narrows-previous']=create(boards['narrows-previous'])
engines['bridges-legacy']=create(boards['bridges-legacy'])
return engines.classic
