local rulebook=require('rules')
local function makeChooser(rules)
  local variants=require('variants')

  local function hitChance(piece)
    return (rules.DIE-rules.classes[piece.class].shield)/rules.DIE
  end

  local function healthBonus(piece)
    local missing=rules.classes[piece.class].hp-piece.hp
    local total=0
    for roll=1,rules.DIE do total=total+math.min(roll,missing) end
    return total/rules.DIE
  end

  -- The opponent gets one reply. Extra attackers matter because they can still
  -- threaten this hex after a kill, but they cannot all hit in the same turn.
  local function danger(state,piece,spot,hp,enemies,removed,armedFort)
    local worst,backup=0,0
    for _,enemy in ipairs(enemies) do
      local attacker=enemy==armedFort and {class='fortress',owner=enemy.owner,r=enemy.r,c=enemy.c,armed=true} or enemy
      if enemy~=removed and rules.canAttack(state,attacker,spot) then
        local power=rules.classes[enemy.class].power
        local loss=math.min(power,hp)+(power>=hp and 35 or 0)
        local risk=hitChance(piece)*loss
        if rules.isCritical(hp,rules.classes[piece.class].hp)
          and rules.isCritical(enemy.hp,rules.classes[enemy.class].hp) then
          risk=.5*(hp+35)
        end
        backup=math.max(backup,math.min(worst,risk))
        worst=math.max(worst,risk)
      end
    end
    return worst+.18*backup
  end

  local function attackValue(piece,target,ownFort)
    if rules.isDeathMatch(piece,target) then
      local value=target.hp*2+23
      if target.class=='fortress' then value=value+46
      elseif rules.distance(target,ownFort)<=3 then value=value+8 end
      local sacrifice=piece.class=='fortress' and 70 or 27+piece.hp
      return .5*(value-sacrifice),false,.5
    end
    local power=rules.classes[piece.class].power
    local kill=power>=target.hp
    local value=2*math.min(power,target.hp)
    if kill then value=value+23+1.8*healthBonus(piece) end
    if target.class=='fortress' then value=value+14
    elseif rules.distance(target,ownFort)<=3 then value=value+8 end
    return hitChance(target)*value,kill,hitChance(target)
  end

  -- Planning uses public state only. A potion's Health roll and the trap map
  -- belong to the rules engine and are never inspected here.
  local function expectedPotionHealth(missing)
    local total=0
    for roll=variants.potionMinHeal,variants.potionMaxHeal do
      total=total+math.min(roll,missing)
    end
    return total/(variants.potionMaxHeal-variants.potionMinHeal+1)
  end

  local function potionClaims(board,pieces)
    local claims={}
    for _,piece in ipairs(pieces) do
      local missing=rules.classes[piece.class].hp-piece.hp
      if missing>0 then
        for key in pairs(rules.moves(board,piece.id)) do
          if board.potions[key] then
            local value=expectedPotionHealth(missing)
            if rules.isCritical(piece.hp,rules.classes[piece.class].hp) then value=value+2 end
            claims[key]=math.max(claims[key] or 0,value)
          end
        end
      end
    end
    return claims
  end

  local function publicTrapOdds(board)
    local visited={}
    if not board.options.traps then return 0,visited end
    local remaining=math.max(0,board.options.trapCount-(board.triggeredTraps or 0))
    for _,token in ipairs(board.history) do
      if token:sub(1,1)=='M' then
        local action=rules.decode(token)
        if action then visited[rules.key(action.r,action.c)]=true end
      end
    end
    local unknown=0
    for r=rules.board.middle-1,rules.board.middle+1 do
      for c=0,rules.rowWidths[r+1]-1 do
        local key=rules.key(r,c)
        if not visited[key] and not board.potions[key] and not board.walls[key] then unknown=unknown+1 end
      end
    end
    return unknown>0 and math.min(1,remaining/unknown) or 0,visited
  end

  local function trapCost(board,action,hp,odds,visited)
    local key=rules.key(action.r,action.c)
    if odds==0 or math.abs(action.r-rules.board.middle)>1 or visited[key] or board.potions[key] or board.walls[key] then
      return 0
    end
    local total=0
    for damage=1,12 do
      total=total+math.min(hp,damage)+(damage>=hp and 35 or 0)
    end
    return odds*total/12
  end

  local function breachValue(before,after,pieces,targets,fort)
    local value=0
    for _,piece in ipairs(pieces) do
      local old=rules.moves(before,piece.id)
      local new=rules.moves(after,piece.id)
      local advance=0
      for key in pairs(new) do
        if not old[key] then
          local r,c=rules.fromkey(key)
          local closer=rules.distance(piece,fort)-rules.distance({r=r,c=c},fort)
          advance=math.max(advance,closer)
        end
      end
      value=value+advance*3
      for _,target in ipairs(targets) do
        if rules.canAttack(after,piece,target) and not rules.canAttack(before,piece,target) then
          value=value+(target==fort and 7 or 3)
          break
        end
      end
    end
    return value
  end

  -- Work back from open passages using visible terrain and troop positions.
  -- Friendly troops can clear a route over several turns. Actual moves still
  -- have to pass the rules engine, including each troop's movement restrictions.
  local function wallRoutes(board,enemies)
    if not board.options.wall and not rules.board.crossings then return nil end
    local row=rules.board.middle
    local forward=board.turn==1 and -1 or 1
    local blocked={}
    for _,piece in ipairs(enemies) do blocked[rules.key(piece.r,piece.c)]=true end
    local gaps={}
    for c=0,rules.rowWidths[row+1]-1 do
      local key=rules.key(row,c)
      local section=board.walls[key]
      if rules.playable(row,c) and not blocked[key] and (not section or section.hp<=0) then
        for _,neighbor in ipairs(rules.neighbors(row,c)) do
          if neighbor.r==row+forward and not blocked[rules.key(neighbor.r,neighbor.c)] then
            gaps[#gaps+1]={r=row,c=c}
            break
          end
        end
      end
    end
    if #gaps==0 then return nil end
    local function distances(forwardOnly)
      local distance,queue={},{}
      for i,gap in ipairs(gaps) do
        distance[rules.key(gap.r,gap.c)]=0
        queue[i]=gap
      end
      local index=1
      while index<=#queue do
        local node=queue[index]
        index=index+1
        local steps=distance[rules.key(node.r,node.c)]
        for _,near in ipairs(rules.neighbors(node.r,node.c)) do
          local key=rules.key(near.r,near.c)
          local allowedDirection=not forwardOnly or near.r==node.r-forward
          if allowedDirection and (near.r-row)*forward<0 and not blocked[key] and not distance[key] then
            distance[key]=steps+1
            queue[#queue+1]=near
          end
        end
      end
      return distance
    end
    return {general=distances(false),forwardOnly=distances(true)},forward
  end

  local function openingProgress(routes,forward,piece,move)
    if not routes then return 0 end
    local row=rules.board.middle
    local fromSide=(piece.r-row)*forward
    local toSide=(move.r-row)*forward
    if fromSide>0 then return 0 end
    local distances=rules.classes[piece.class].forward and routes.forwardOnly or routes.general
    local from=distances[rules.key(piece.r,piece.c)]
    if toSide>0 then return from and 3 or 2 end
    local to=distances[rules.key(move.r,move.c)]
    if not to then return 0 end
    if not from then return 1 end
    return math.max(0,from-to)+(to==0 and fromSide<0 and 1 or 0)
  end

  -- On custom footprints, hex distance alone can point a troop straight into
  -- a gap. Work backward from the keep through the visible, usable approaches.
  local function siegeRoutes(state,enemyFort,openOnly)
    local keepKey=rules.key(enemyFort.r,enemyFort.c)
    local ownFort=state.forts[state.turn]
    local ownKey=rules.key(ownFort.r,ownFort.c)
    local function open(spot)
      local key=rules.key(spot.r,spot.c)
      local wall=state.walls[key]
      return key~=ownKey and (not wall or wall.hp<=0)
    end
    local function distances(goals,forwardOnly)
      local distance,queue={},{}
      for _,spot in ipairs(goals) do
        distance[rules.key(spot.r,spot.c)]=0
        queue[#queue+1]=spot
      end
      local head=1
      while queue[head] do
        local spot=queue[head]
        head=head+1
        for _,near in ipairs(rules.neighbors(spot.r,spot.c)) do
          local key=rules.key(near.r,near.c)
          if (not forwardOnly or spot.r==rules.soldierMoveRow(near.r,state.turn)) and not distance[key] and open(near) then
            distance[key]=distance[rules.key(spot.r,spot.c)]+1
            queue[#queue+1]=near
          end
        end
      end
      return distance
    end
    local goals={enemyFort}
    local openRoute,forwardRoute=distances(goals,false),distances(goals,true)
    if openOnly then return {openRoute,forwardRoute} end
    local staging={}
    for _,section in pairs(state.walls) do
      if section.hp>0 then
        for _,near in ipairs(rules.neighbors(section.r,section.c)) do
          local key=rules.key(near.r,near.c)
          if key~=keepKey and open(near) then staging[key]=near end
        end
      end
    end
    local approaches={}
    for _,spot in pairs(staging) do approaches[#approaches+1]=spot end
    return {openRoute,forwardRoute,distances(approaches,false),distances(approaches,true)}
  end

  local function siegeProgress(routes,piece,action)
    local from,to=rules.key(piece.r,piece.c),rules.key(action.r,action.c)
    local forwardOnly=rules.classes[piece.class].forward
    local direct=routes[forwardOnly and 2 or 1]
    local staging=routes[forwardOnly and 4 or 3]
    if direct[from] and direct[to] then return direct[from]-direct[to] end
    if direct[to] then return 3 end
    if direct[from] then return -3 end
    if staging[from] and staging[to] then return staging[from]-staging[to] end
    if staging[to] then return 1 end
    return 0
  end

  -- Prefer a breach that connects real approaches to the enemy keep. A hole
  -- beside a void or on the wrong side of a Soldier may offer no way through.
  local function breachAccess(before,after,allies)
    local gained=0
    for _,piece in ipairs(allies) do
      if piece.class~='fortress' then
        local route=rules.classes[piece.class].forward and 2 or 1
        local key=rules.key(piece.r,piece.c)
        local old,new=before[route][key],after[route][key]
        if new then gained=gained+(old and math.min(3,math.max(0,old-new)) or 3) end
      end
    end
    return math.min(9,gained)
  end

  local function choose(state,random)
    local ownFort,enemyFort=state.forts[state.turn],state.forts[3-state.turn]
    local allies,enemies={ownFort},{enemyFort}
    local fortThreats={}
    local nearby,firing=0,0
    for _,unit in ipairs(state.units) do
      if unit.hp>0 then
        if unit.owner==state.turn then
          allies[#allies+1]=unit
        else
          enemies[#enemies+1]=unit
          local distance=rules.distance(unit,ownFort)
          local canHit=rules.canAttack(state,unit,ownFort)
          if distance<=2 then nearby=nearby+1 end
          if canHit then firing=firing+1 end
          if distance<=2 or canHit then fortThreats[unit.id]=canHit and 2 or 1 end
        end
      end
    end
    local last=state.last
    local attacked=last and last.defenderClass=='fortress' and last.actor~=state.turn
    local coordinated=nearby>=3 or firing>=2
    local defense=math.min(12,nearby*1.5+firing*3)
    if coordinated then defense=defense+7 end
    if attacked then defense=defense+8
    elseif ownFort.armed and firing>0 then defense=defense+4 end
    if firing>0 and ownFort.hp<=rules.FORT_HP*.25 then defense=defense+10 end
    local recentMoves={}
    for i=#state.history-1,math.max(1,#state.history-11),-2 do
      local token=state.history[i]
      recentMoves[token]=(recentMoves[token] or 0)+1
    end
    local quietTurns=0
    for i=#state.history,math.max(1,#state.history-23),-1 do
      local kind=state.history[i]:sub(1,1)
      if kind=='A' or kind=='D' then break end
      quietTurns=quietTurns+1
    end
    -- After a long stretch without combat, take more chances to break the standoff.
    local urgency=math.max(0,(quietTurns-8)/16)
    local caution=1-.65*urgency
    local setupWeight=.14+.14*urgency
    local originRisk,breaches={},{}
    local enemyView=setmetatable({turn=3-state.turn},{__index=state})
    local ownClaims,enemyClaims
    if state.options.destroyPotions and next(state.potions) then
      ownClaims=potionClaims(state,allies)
      enemyClaims=potionClaims(enemyView,enemies)
    end
    local odds,visited=publicTrapOdds(state)
    local routes,forward
    local siege
    if rules.board.gaps or rules.board.id=='narrows-legacy' then
      siege=siegeRoutes(state,enemyFort)
    else
      routes,forward=wallRoutes(state,enemies)
    end
    local breachRoutes
    local actions=rules.actions(state)
    local progress,hasSafeAdvance={},false
    if routes or siege then
      for _,action in ipairs(actions) do
        if action.type=='move' then
          local piece=rules.piece(state,action.id)
          local advance=siege and siegeProgress(siege,piece,action) or openingProgress(routes,forward,piece,action)
          if advance>0 then
            progress[action]=advance
            if not hasSafeAdvance then
              local risk=danger(state,piece,action,piece.hp,enemies)+trapCost(state,action,piece.hp,odds,visited)
              local key=rules.key(action.r,action.c)
              local route=rules.classes[piece.class].forward and 2 or 1
              hasSafeAdvance=risk<=8 and (not siege or siege[route][key]~=nil)
            end
          end
        end
      end
    end
    local best,bestScore=nil,-math.huge
    for _,action in ipairs(actions) do
      if action.type=='pass' then return action end
      local piece=rules.piece(state,action.id)
      if not originRisk[piece.id] then
        originRisk[piece.id]=danger(state,piece,piece,piece.hp,enemies)
      end
      local score
      if action.type=='crate' then
        -- Clear a risky crossing for nearby allies. Unknown contents are a fair coin.
        score=-7-originRisk[piece.id]
        for _,ally in ipairs(allies) do
          if ally.class~='fortress' and ally.hp<=variants.crateHealth and rules.distance(ally,action)<=2 then
            score=math.max(score,10-originRisk[piece.id])
          end
        end
      elseif action.type=='potion' then
        local key=rules.key(action.r,action.c)
        score=-6+3.2*(enemyClaims[key] or 0)-1.8*(ownClaims[key] or 0)-originRisk[piece.id]
      elseif action.type=='attack' then
        local target=rules.occupied(state,action.r,action.c).ref
        if target.class=='wall' then
          local power=rules.classes[piece.class].power
          local odds=(rules.DIE-target.shield)/rules.DIE
          local key=rules.key(action.r,action.c)
          local breach=breaches[key]
          if not breach then
            local walls={}
            for index,section in pairs(state.walls) do
              if index~=key then walls[index]=section end
            end
            local opened=setmetatable({walls=walls},{__index=state})
            local enemyOpened=setmetatable({turn=enemyView.turn,walls=walls},{__index=state})
            local value=breachValue(state,opened,allies,enemies,enemyFort)
              -.45*breachValue(enemyView,enemyOpened,enemies,allies,ownFort)
            if rules.board.id~='classic' then
              breachRoutes=breachRoutes or siege or siegeRoutes(state,enemyFort,true)
              value=value+breachAccess(breachRoutes,siegeRoutes(opened,enemyFort,true),allies)
            end
            breach={value=value,board=opened}
            breaches[key]=breach
          end
          local opens=power>=target.hp
          local reply=opens and danger(breach.board,piece,piece,piece.hp,enemies) or originRisk[piece.id]
          local progress=power/math.max(power,target.hp)
          score=(math.min(power,target.hp)+progress*(9+math.max(-5,breach.value)))*odds
            +13*urgency-.65*(originRisk[piece.id]+odds*(reply-originRisk[piece.id]))
          -- Opening another section is secondary when troops can advance safely.
          if hasSafeAdvance then score=score*.52 end
        else
          local value,kill,odds=attackValue(piece,target,ownFort)
          if kill and target==enemyFort then return action end
          local armedFort=target==enemyFort and target or nil
          local missRisk=danger(state,piece,piece,piece.hp,enemies,nil,armedFort)
          local hitRisk=missRisk
          if rules.isDeathMatch(piece,target) then
            hitRisk=danger(state,piece,piece,piece.hp,enemies,target)
            missRisk=0
          elseif kill then
            hitRisk=0
            for roll=1,rules.DIE do
              local healed=math.min(piece.hp+roll,rules.classes[piece.class].hp)
              hitRisk=hitRisk+danger(state,piece,piece,healed,enemies,target)/rules.DIE
            end
          end
          local replyRisk=odds*hitRisk+(1-odds)*missRisk
          score=value+caution*(.85*(originRisk[piece.id]-replyRisk)-.35*replyRisk)+12*urgency
          local threat=fortThreats[target.id]
          if threat then score=score+defense*threat*(.5+.5*odds) end
        end
      else
        local from=rules.distance(piece,enemyFort)
        local to=rules.distance(action,enemyFort)
        local hp=piece.hp
        local risk=danger(state,piece,action,hp,enemies)
        local potionValue=0
        if state.potions[rules.key(action.r,action.c)] and hp<rules.classes[piece.class].hp then
          local maximum=rules.classes[piece.class].hp
          potionValue=expectedPotionHealth(maximum-hp)
          local total=0
          for roll=variants.potionMinHeal,variants.potionMaxHeal do
            total=total+danger(state,piece,action,math.min(maximum,hp+roll),enemies)
          end
          risk=total/(variants.potionMaxHeal-variants.potionMinHeal+1)
          hp=hp+potionValue
        end
        if state.crates[rules.key(action.r,action.c)] then
          local heal=math.min(variants.crateHealth,rules.classes[piece.class].hp-hp)
          local damage=math.min(variants.crateHealth,hp)
          local afterDamage=hp-damage
          local bombRisk=afterDamage>0 and danger(state,piece,action,afterDamage,enemies) or 0
          risk=(danger(state,piece,action,hp+heal,enemies)+bombRisk)*.5
          potionValue=(heal-damage-(afterDamage==0 and 35 or 0))*.5
        end
        local nextAttack,coverageGain=0,0
        local destination={r=action.r,c=action.c,class=piece.class,owner=piece.owner,hp=hp}
        for _,target in ipairs(enemies) do
          local canHit=rules.canAttack(state,destination,target)
          local covered=rules.canAttack(state,piece,target)
          -- A Barbarian closes to melee to open a new attack. The reply risk below
          -- still accounts for the defender and other enemies that can hit that hex.
          if canHit and (piece.class~='barbarian' or not covered) then
            local value=attackValue(destination,target,ownFort)
            local weight=setupWeight+(piece.class=='barbarian' and .24 or 0)
            nextAttack=math.max(nextAttack,value*weight)
          end
          local threat=fortThreats[target.id]
          if threat then
            if canHit and not covered then coverageGain=coverageGain+threat
            elseif covered and not canHit then coverageGain=coverageGain-threat end
          end
        end
        local advance=siege and siegeProgress(siege,piece,action) or from-to
        score=math.min(3,advance)*4.8+(to<=3 and 3 or 0)
          +caution*(1.45*(originRisk[piece.id]-risk)-.35*risk)+nextAttack
        -- Before clearing the bridge, favor safe progress toward a usable lane.
        -- The terrain routes distinguish an open lane from a sealed one.
        if rules.board.bridgeLanes and progress[action] and risk<=8
          and (piece.r-rules.board.middle)*(state.turn==1 and -1 or 1)<=0 then
          score=score+2*math.min(3,progress[action])
        end
        if rules.resurrectionMove(state,piece,action.r,action.c) then
          local bestUpgrade=-math.huge
          for i,kind in ipairs(rules.resurrectionClasses) do
            local stats=rules.classes[kind]
            local warrior={r=action.r,c=action.c,class=kind,owner=piece.owner,hp=stats.hp}
            local upgrade=.45*stats.hp+1.4*stats.power+1.1*stats.shield+(stats.move or 2)
              -danger(state,warrior,warrior,warrior.hp,enemies)
            for _,target in ipairs(enemies) do
              if rules.canAttack(state,warrior,target) then
                upgrade=upgrade+(target==enemyFort and 8 or 3)
              end
            end
            if upgrade>bestUpgrade then bestUpgrade,action.resurrection=upgrade,i end
          end
          score=score+math.max(6,math.min(25,.55*bestUpgrade))
        end
        score=score+2*potionValue-trapCost(state,action,piece.hp,odds,visited)
        if progress[action] and not siege then
          local weight=rules.classes[piece.class].projectile and 4 or 10
          score=score+weight*progress[action]
        end
        if defense>0 then
          local homeFrom,homeTo=rules.distance(piece,ownFort),rules.distance(action,ownFort)
          local closing=math.min(5,homeFrom)-math.min(5,homeTo)
          score=score+defense*(.32*closing+.44*math.max(-3,math.min(3,coverageGain)))
        end
        score=score-7*(recentMoves[rules.encode(action)] or 0)
        local previous=state.previous
        if previous and previous.actor==state.turn and previous.type=='move' and previous.id==piece.id
          and action.r==previous.from.r and action.c==previous.from.c then
          score=score-(risk>=originRisk[piece.id] and 17 or 4)
        end
      end
      score=score+random()*1.1
      if score>bestScore then best,bestScore=action,score end
    end
    return best
  end

  return choose
end

local choosers={}
return function(board,random)
  local id=board.boardId or 'classic'
  local choose=choosers[id]
  if not choose then
    choose=makeChooser(rulebook.forBoard(id))
    choosers[id]=choose
  end
  return choose(board,random)
end
