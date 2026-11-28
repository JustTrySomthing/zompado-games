local boards=require('boards')
local fullWallCodes={skirmish=9,wide=10}
local variants={row=5,potionMinHeal=3,potionMaxHeal=8,crateHealth=12}

function variants.defaults(id)
  local board=boards[id or 'classic']
  return {board=board.id,resurrection=false,traps=false,trapCount=3,wall=false,wallHealth=16,wallShield=3,overWall=false,
    potions=false,potionCount=2,destroyPotions=false,
    crates=false,crateCount=board.crateCount,destroyCrates=false,legacyCrates=false,legacyCratePlacement=false,legacyBridgeWall=false,legacyFlankWall=false}
end

function variants.encode(options)
  local base=('%d_%d_%d_%d_%d_%d'):format(options.traps and 1 or 0,options.trapCount,
    options.wall and 1 or 0,options.wallHealth,options.wallShield,options.overWall and 1 or 0)
  if options.board and options.board~='classic' then
    -- B4 retains its previous two-section layout in saved histories.
    local code=options.board=='bridges-legacy' and options.wall and not options.legacyBridgeWall
      and 6 or boards[options.board].code
    if options.wall and not options.legacyFlankWall then code=fullWallCodes[options.board] or code end
    base=('B%d_'):format(code)..base
  end
  local resurrection=options.resurrection and '_Q' or ''
  if options.crates then
    local scatter=boards[options.board or 'classic'].scatteredCrates and not options.legacyCratePlacement
    local format=options.legacyCrates and 'C' or scatter and 'G' or 'M'
    return base..('_%s%d_%d'):format(format,options.crateCount,options.destroyCrates and 1 or 0)..resurrection
  end
  if options.potions then
    return base..('_%d_%d'):format(options.potionCount,options.destroyPotions and 1 or 0)..resurrection
  end
  return base..resurrection
end

function variants.enabled(options)
  return options.resurrection or options.wall or options.traps or options.potions or options.crates
    or options.board and options.board~='classic'
end

function variants.decode(value)
  if not value then return variants.defaults() end
  local resurrection=value:sub(-2)=='_Q'
  if resurrection then value=value:sub(1,-3) end
  local board=boards.classic
  local code,body=value:match('^B([1-9]%d?)_(.+)$')
  if code then
    board,value=boards.byCode[tonumber(code)] or (code=='9' and boards.skirmish or code=='10' and boards.wide),body
    if not board or board==boards.classic then return nil end
  end
  local classic,crateFormat,crates,shoot=value:match('^(.+)_([CGM])([1-9])_([01])$')
  if classic then value=classic end
  local base,potions,destroy=value:match('^(.+)_([1-3])_([01])$')
  local fields='^([01])_([1-9])_([01])_(%d%d?)_(%d%d?)_([01])$'
  if not base or not base:match(fields) then base,potions,destroy=value,nil,nil end
  local traps,count,wall,health,shield,over=base:match(fields)
  count,health,shield=tonumber(count),tonumber(health),tonumber(shield)
  if (code=='6' or code=='9' or code=='10') and wall~='1' then return nil end
  if crateFormat=='G' and not board.scatteredCrates then return nil end
  if not health or health<1 or health>50 or shield>11
    or crates and (traps=='1' or potions) then return nil end
  if board~=boards.classic and (traps=='1' or potions or crateFormat=='C' or (tonumber(crates) or 0)>6) then
    return nil
  end
  return {board=board.id,resurrection=resurrection,legacyBridgeWall=code=='4' and wall=='1',
    legacyFlankWall=(code=='2' or code=='5') and wall=='1',traps=traps=='1',trapCount=count,wall=wall=='1',wallHealth=health,wallShield=shield,overWall=over=='1',
    potions=potions~=nil,potionCount=tonumber(potions) or 2,destroyPotions=destroy=='1',
    crates=crates~=nil,crateCount=tonumber(crates) or board.crateCount,destroyCrates=shoot=='1',legacyCrates=crateFormat=='C',
    legacyCratePlacement=crateFormat=='M' or crateFormat=='C'}
end

function variants.wallBounds(options,rules)
  local last=rules.rowWidths[variants.row+1]-1
  if options.crates and options.crateCount==9 and not options.legacyCrates then
    return 1,last-1
  end
  return 0,last
end

-- Rank each candidate by its distance from the nearest crate already placed.
-- Backtrack if a wide gap would otherwise leave too few hexes for the full count.
local function spreadCrates(candidates,count,rules,minGap,randomOrder)
  local picked={}
  local function place(available)
    if #picked==count then return true end
    local ranked={}
    for _,spot in ipairs(available) do
      local gap=rules.ROWS
      for _,other in ipairs(picked) do gap=math.min(gap,rules.distance(spot,other)) end
      ranked[#ranked+1]={spot=spot,gap=gap}
    end
    table.sort(ranked,function(a,b)
      if not randomOrder and a.gap~=b.gap then return a.gap>b.gap end
      return a.spot.order<b.spot.order
    end)
    for i=1,#ranked-(count-#picked)+1 do
      local spot=ranked[i].spot
      local nextSpots={}
      for j=i+1,#ranked do
        local other=ranked[j].spot
        if rules.distance(spot,other)>=minGap then nextSpots[#nextSpots+1]=other end
      end
      picked[#picked+1]=spot
      if #nextSpots>=count-#picked and place(nextSpots) then return true end
      picked[#picked]=nil
    end
    return false
  end
  if place(candidates) then return picked end
end

function variants.wallColumns(options,rules)
  if rules.board.id=='bridges-legacy' and options.legacyBridgeWall then return {2,6} end
  local full=fullWallCodes[rules.board.id] and not options.legacyFlankWall
  if rules.board.wall and not full then return rules.board.wall end
  local first,last
  if full then first,last=0,rules.rowWidths[rules.board.middle+1]-1
  else first,last=variants.wallBounds(options,rules) end
  local columns={}
  for c=first,last do columns[#columns+1]=c end
  return columns
end

function variants.setup(board,rules,options)
  local row=rules.board.middle
  board.options=variants.defaults(rules.board.id)
  for key in pairs(board.options) do
    if options and options[key]~=nil then board.options[key]=options[key] end
  end
  board.walls,board.traps,board.potions={},{},{}
  board.crates,board.crateContents,board.scorches={},{},{}
  if board.options.wall then
    local function addWall(r,c)
      board.walls[rules.key(r,c)]={r=r,c=c,class='wall',owner=0,
        hp=board.options.wallHealth,shield=board.options.wallShield}
    end
    if rules.board.wallRing then
      for _,cell in ipairs(rules.board.wallRing) do addWall(cell[1],cell[2]) end
    else
      for _,c in ipairs(variants.wallColumns(board.options,rules)) do addWall(row,c) end
    end
  end
  if board.options.traps then
    local spots={}
    for r=row-1,row+1 do
      for c=0,rules.rowWidths[r+1]-1 do
        local key=rules.key(r,c)
        if not board.walls[key] then spots[#spots+1]=key end
      end
    end
    -- Use a separate stream so placement never alters the combat dice.
    local random={rng=(board.seed*2381+293)%2147483646+1}
    for _=1,board.options.trapCount do
      local i=rules.next_random(random,#spots)
      board.traps[table.remove(spots,i)]=rules.next_random(random,12)
    end
  end
  if board.options.potions then
    local spots={}
    for r=row-1,row+1 do
      for c=0,rules.rowWidths[r+1]-1 do
        local key=rules.key(r,c)
        if not board.walls[key] and not board.traps[key] then
          spots[#spots+1]={r=r,c=c}
        end
      end
    end
    local random={rng=(board.seed*6421+919)%2147483646+1}
    for _=1,board.options.potionCount do
      local spot=table.remove(spots,rules.next_random(random,#spots))
      spot.heal=variants.potionMinHeal-1+rules.next_random(random,variants.potionMaxHeal-variants.potionMinHeal+1)
      board.potions[rules.key(spot.r,spot.c)]=spot
    end
  end
  if board.options.crates then
    local spots={}
    local function addSpots(r)
      for c=0,rules.rowWidths[r+1]-1 do
        local key=rules.key(r,c)
        local reserved=board.options.resurrection
          and (rules.resurrectionSite(board,1,r,c) or rules.resurrectionSite(board,2,r,c))
        if not reserved and rules.playable(r,c) and not rules.occupied(board,r,c)
          and not board.traps[key] and not board.potions[key] then
          spots[#spots+1]={r=r,c=c}
        end
      end
    end
    local scatter=rules.board.scatteredCrates and not board.options.legacyCratePlacement and not board.options.legacyCrates
    local first,last=row-1,row+1
    if scatter then first,last=0,rules.ROWS-1 end
    for r=first,last do addSpots(r) end
    -- Content and placement use separate streams, independent of combat.
    local places={rng=(board.seed*4733+109)%2147483646+1}
    local contents={rng=(board.seed*8849+431)%2147483646+1}
    local count=board.options.crateCount
    if board.options.legacyCrates then
      -- Existing saves replay with their original locations and contents.
      for _=1,count do
        local spot=table.remove(spots,rules.next_random(places,#spots))
        local key=rules.key(spot.r,spot.c)
        board.crates[key]=spot
        board.crateContents[key]=rules.next_random(contents,2)==1 and 'potion' or 'bomb'
      end
      return
    end
    local function shuffle(from)
      for i=#spots,from+1,-1 do
        local j=from-1+rules.next_random(places,i-from+1)
        spots[i],spots[j]=spots[j],spots[i]
      end
      for i=from,#spots do spots[i].order=i end
    end
    shuffle(1)
    local selected=count<=5 and spreadCrates(spots,count,rules,3,scatter)
      or spreadCrates(spots,count,rules,2,scatter)
    if not selected and not scatter then
      -- With the wall enabled, nine crates require some open flank hexes.
      local from=#spots+1
      addSpots(row-2)
      addSpots(row+2)
      shuffle(from)
      selected=spreadCrates(spots,count,rules,2)
      if not selected and rules.board.id~='classic' then
        -- Broaden the search to unoccupied home-side spaces only when the center cannot fit the count.
        from=#spots+1
        for r=0,rules.ROWS-1 do
          if math.abs(r-row)>2 then addSpots(r) end
        end
        shuffle(from)
        selected=spreadCrates(spots,count,rules,2)
      end
    end
    assert(selected,'No spaced crate layout')
    local potion,bomb
    if count>1 then
      potion=rules.next_random(contents,count)
      bomb=rules.next_random(contents,count-1)
      if bomb>=potion then bomb=bomb+1 end
    end
    for i,spot in ipairs(selected) do
      local key=rules.key(spot.r,spot.c)
      board.crates[key]={r=spot.r,c=spot.c}
      board.crateContents[key]=i==potion and 'potion' or i==bomb and 'bomb'
        or (rules.next_random(contents,2)==1 and 'potion' or 'bomb')
    end
  end
end

-- Determine which section a straight shot or teleport would cross.
-- A ray on the boundary of two hexes is blocked by either intact section.
function variants.blocked(board,from,to,rules)
  if not board.options.wall then return false end
  local function centerX(p)
    return p.c+(rules.COLS-rules.rowWidths[p.r+1])/2
  end
  if rules.board.wallRing then
    -- Clip the ray against each point-up wall hex. x is in horizontal hex
    -- pitches and y is in row steps. The six edges are paired half-plane bounds.
    local fx,tx=centerX(from),centerX(to)
    local function touches(section)
      if (section.r==from.r and section.c==from.c) or (section.r==to.r and section.c==to.c) then return false end
      local x,y=fx-centerX(section),from.r-section.r
      local dx,dy=tx-fx,to.r-from.r
      local first,last=0,1
      local function inside(origin,slope)
        if slope>0 then last=math.min(last,(.50001-origin)/slope)
        elseif slope<0 then first=math.max(first,(.50001-origin)/slope)
        elseif origin>.50001 then return false end
        return first<=last
      end
      return inside(x,dx) and inside(-x,-dx)
        and inside(.5*x+.75*y,.5*dx+.75*dy) and inside(-.5*x-.75*y,-.5*dx-.75*dy)
        and inside(.5*x-.75*y,.5*dx-.75*dy) and inside(-.5*x+.75*y,-.5*dx+.75*dy)
    end
    for _,section in pairs(board.walls) do
      if section.hp>0 and touches(section) then return true end
    end
    return false
  end
  local row=rules.board.middle
  if from.r==row and to.r==row then
    for c=math.min(from.c,to.c)+1,math.max(from.c,to.c)-1 do
      local section=board.walls[rules.key(row,c)]
      if section and section.hp>0 then return true end
    end
    return false
  end
  if (from.r-row)*(to.r-row)>=0 then return false end
  local x=centerX(from)+(centerX(to)-centerX(from))*(row-from.r)/(to.r-from.r)
    -(rules.COLS-rules.rowWidths[row+1])/2
  if board.replayingNarrows150 then
    x=math.max(0,math.min(rules.rowWidths[row+1]-1,x))
  end
  for c=math.max(0,math.ceil(x-.50001)),math.min(rules.rowWidths[row+1]-1,math.floor(x+.50001)) do
    local section=board.walls[rules.key(row,c)]
    if section and section.hp>0 then return true end
  end
  return false
end

return variants
