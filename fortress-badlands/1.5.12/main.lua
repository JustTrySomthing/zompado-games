-- Fortress Siege: Final Conquest — Zompa SDK v5 / LÖVE 11.5.
-- This game's deterministic rules are shared by solo, pass-and-play, and turns-v2 online.
local rules = require('rules')
local zompa = require('zompa')
local chooseCpuAction = require('cpu')
local moveFx = require('movement_fx')
local mode = 'solo'
local state, onlineSide, onlineAllowed, onlineReady, lastOnlineCount
local selected, inspected, targets, pending, overlay, intended, actionBox, cancelBox, inspectedFortOwner
local layout, timers, notice, blocked = {}, {cpu=0,poll=0,dialog=0}, '', nil
timers.rulebook=rules
timers.variantUI=require('variant_ui')
timers.variants=require('variants')
timers.projectiles=require('battle_projectiles')
timers.finaleArt=require('finale_art')
local saveVersionChanged,turnSendFailed
-- Visual movement never alters rules, health, online tokens or saved state.
local moving, queuedEvent, cardBox = nil, nil, nil
local CINEMATIC_SPEED=.5
local animationTime=0
local selectionAge=0
local finishElapsed=0 -- presentation only; no changes to match history
local palette = {
  sky={0.055,0.075,0.115}, top={0.18,0.27,0.43}, bottom={0.37,0.17,0.20},
  waste={0.30,0.28,0.23}, border={0.08,0.09,0.12}, gold={0.93,0.76,0.45},
  green={0.21,0.79,0.48}, red={0.96,0.38,0.34}, text={0.94,0.93,0.88},
}
-- Strong class identities are drawn as vectors, independent of finished artwork.
local classColors={
  soldier={0.70,0.66,0.52}, barbarian={0.53,0.34,0.19},
  assassin={0.42,0.48,0.53}, wizard={0.48,0.37,0.62},
  ogre={0.43,0.50,0.29}, archer={0.67,0.48,0.29},
}
local teamColors={[1]={0.50,0.15,0.20},[2]={0.15,0.30,0.46}}
local fonts={}
local teamNames={'Red','Blue'}
local teamLabels={{1,.52,.46},{.55,.79,1}}
local onlineOpeningPrompt={}
local intro, logo, horn, arena, valley
local siegeKeeps,siegeChunks={},{}
local introTime=0
local introDuration=4.3
local function smoothstep(t)
  t=math.max(0,math.min(1,t))
  return t*t*(3-2*t)
end
local artBoard, unitArt = nil, { [1]={}, [2]={} }
-- Individually loaded character busts and board tokens; never a flattened UI.
local portraitArt,fortArt = { [1]={}, [2]={} }, {}
local fighterArt = {{},{}}
local mixer = zompa.audio()
local score
local scoreCheck, scorePosition = 0, 0
local cues, cueCounts={},{}
local cuePitches={1,.966,1.04,.989,1.022}
local function playCue(name,pitch)
  local source=cues[name]
  if not source then return end
  source:stop()
  local index=(cueCounts[name] or 0)%#cuePitches+1
  cueCounts[name]=index
  if source.setPitch then source:setPitch((pitch or 1)*cuePitches[index]) end
  source:play()
end
local hurtIndex=0
local function playHurt(class)
  if class=='fortress' or class=='wall' then return end
  hurtIndex=hurtIndex%4+1
  local pitch=class=='ogre' and .78 or class=='barbarian' and .91 or 1
  playCue('hurt-'..hurtIndex,pitch)
end
local function crossedCue(before,after,beat,name)
  -- A paused or stuttering device can skip a visual beat. Skip stale sounds too.
  if before<beat and after>=beat and after-beat<=.30 then playCue(name) end
end
local function color(p,a) love.graphics.setColor(p[1],p[2],p[3],a or 1) end
local function frame(x,y,w,h,alpha,radius)
  local g=love.graphics
  local corner=radius or 10
  g.setColor(.72,.58,.36,alpha)
  g.setLineWidth(1.35)
  g.rectangle('line',x,y,w,h,corner,corner)
  g.setColor(1,.85,.55,alpha*.26)
  g.setLineWidth(1)
  g.line(x+corner,y+2,x+w-corner,y+2)
end
local function text(str,x,y,w,align,font)
  color(palette.text)
  love.graphics.setFont(font or fonts.small)
  love.graphics.printf(tostring(str),x,y,w,align or 'center')
end
-- Texture and gameplay use exactly the same 7x10 coordinate map.
-- Pixel centers measured from the approved original art, not inferred
-- from tile edges or a distorted image-generation crop.
local ART_W, ART_H = 984, 1383
local SOURCE_CX, SOURCE_CY = 97, 107 -- calibrated against inset-hex centers
local PITCH_X, PITCH_Y = 131.5, 132.5
-- Truly edge-sharing point-up hexagon positions. Display coordinates are
-- staggered but game indexes/rules remain the existing 7x10, 58-cell graph.
-- Adjacent flat stone edges now meet without empty channels or overlaps.
local SQRT3=math.sqrt(3)
local function center(r,c,engine,view)
  engine,view=engine or rules,view or layout
  local n=engine.rowWidths[r+1]
  return view.x+view.hexStepX*(c+.5+(engine.COLS-n)*.5),
         view.y+view.hexR+view.hexStepY*r
end
local function xyToCell(x,y)
  -- Hit test against the *drawn* hexagon, not a phantom square slot.
  -- The touch polygon is the visible hex itself.
  local R=layout.hexR
  for r=0,rules.ROWS-1 do
    for c=0,rules.COLS-1 do
      if rules.playable(r,c) then
        local hx,hy=center(r,c)
        local dx,dy=math.abs(x-hx),math.abs(y-hy)
        if dx<=SQRT3*R*.5+0.4 and
           dy<=R-dx/SQRT3+0.4 then
          return {r=r,c=c}
        end
      end
    end
  end
  return nil
end
local function fontHeight(font)
  return font.getHeight and font:getHeight() or font.size
end
local function reflow(viewportW,viewportH)
  -- Keep the board upright in a centered portrait stage on wide displays.
  local w=math.max(1,math.min(viewportW,math.floor(viewportH*.76)))
  local safeBottom=viewportH
  if love.window and love.window.getSafeArea then
    local _,y,_,safeH=love.window.getSafeArea()
    if safeH and safeH>0 then safeBottom=math.min(viewportH,y+safeH) end
  end
  -- Leave room inside the hosted canvas for Android's bottom chrome.
  local h=safeBottom-math.min(36,math.max(24,safeBottom*.06))
  local uiScale=math.min(1,h/540)
  local function responsiveFont(target, noSmaller, noLarger)
    return love.graphics.newFont(math.floor(math.max(noSmaller,math.min(noLarger,target*uiScale))+.5))
  end
  fonts.small=responsiveFont(w*.046,11,19)
  fonts.stat=responsiveFont(w*.044,12,18)
  fonts.medium=responsiveFont(w*.055,14,24)
  fonts.large=responsiveFont(w*.079,16,34)
  fonts.finale=responsiveFont(w*.12,22,52)
  local statH,titleH=fontHeight(fonts.stat),fontHeight(fonts.medium)
  fonts.cardStat=responsiveFont(w*.041,11,16)
  fonts.cardLabel=responsiveFont(w*.032,10,13)
  fonts.cardHint=responsiveFont(w*.031,10,14)
  fonts.guide=responsiveFont(w*.039,12,16)
  fonts.openingSide=responsiveFont(w*.042,12,18)
  local statPadding=5
  local cardStatH=fontHeight(fonts.cardStat)
  local statColumns=w>=355 and 4 or 2
  local statBandH=(4/statColumns)*cardStatH+statPadding*2+(statColumns==2 and 4 or 0)
  local cardHintH=fontHeight(fonts.cardHint)+3
  local cardH=4+titleH+2+statH+8+statBandH+cardHintH+6
  local topReserve=cardH+15
  local actionH=math.floor(math.max(36,48*uiScale)+.5)
  local actionGap=math.max(15,math.min(25,math.floor(h*.038+.5)))
  local bottomReserve=actionH+actionGap+4
  local boundW=rules.COLS*SQRT3
  local boundH=(rules.ROWS-1)*1.5+2
  local R=math.max(4,math.min((w-8)/boundW,
    (h-topReserve-bottomReserve)/boundH))
  local boardW,boardH=boundW*R,boundH*R
  local top=topReserve+math.max(0,(h-topReserve-bottomReserve-boardH)*.5)
  layout={w=w,h=h,viewportW=viewportW,stageX=math.floor((viewportW-w)*.5),viewportH=viewportH,hexR=R,hexStepX=SQRT3*R,hexStepY=1.5*R,
    -- Keep the established sprite fit and all existing UI sizing hooks.
    scale=(R*.93)/60,cell=SQRT3*R,radius=R*.84,
    tileW=SQRT3*R,rowH=R*1.5,
    x=(w-boardW)*.5,y=top,boardW=boardW,boardH=boardH,
    cardY=3,cardH=cardH,topReserve=topReserve,
    statBandH=statBandH,statPadding=statPadding,cardHintH=cardHintH,statColumns=statColumns,
    actionH=actionH,actionY=top+boardH+actionGap}
end
local function faceHex(cx,cy,r)
  local coords={}
  for i=0,5 do
    local a=math.rad(i*60-90)
    coords[#coords+1]=cx+r*math.cos(a)
    coords[#coords+1]=cy+r*math.sin(a)
  end
  return coords
end

-- Piece art is full-bleed and centered. The same mask and border are used
-- on the board, in the fortress inspector and in battles.
local BADGE_R=60
local function drawBadgeSprite(sprite,x,y,scale,opacity)
  local g=love.graphics
  local borderR=BADGE_R*scale*.88
  local stencil=g.stencil and g.setStencilTest
  if stencil then
    g.stencil(function()
      g.polygon('fill',faceHex(x,y,borderR))
    end,'replace',1)
    g.setStencilTest('greater',0)
  end
  g.setColor(1,1,1,opacity or 1)
  local iw,ih=sprite:getDimensions()
  local side=borderR*2
  g.draw(sprite,x-borderR,y-borderR,0,side/iw,side/ih)
  if stencil then g.setStencilTest() end
  -- Thin, uninterrupted outer edge. No offset shadow hex or extra left lip.
  g.setColor(.97,.78,.35,opacity or 1)
  g.setLineWidth(math.max(1.05,2.0*scale))
  g.polygon('line',faceHex(x,y,borderR))
end

local function emblem(kind,cx,cy,rad)
  -- Each symbol differs in silhouette and color (color is never the sole cue).
  love.graphics.setColor(0.985,0.975,0.88,1)
  love.graphics.setLineWidth(math.max(1.5,rad*0.14))
  if kind=='soldier' then
    love.graphics.line(cx-rad*.55,cy+rad*.6,cx+rad*.53,cy-rad*.52)
    love.graphics.line(cx-rad*.52,cy-rad*.45,cx+rad*.51,cy+rad*.54)
    love.graphics.line(cx-rad*.65,cy+rad*.40,cx-rad*.35,cy+rad*.69)
  elseif kind=='barbarian' then
    love.graphics.line(cx-rad*.43,cy+rad*.73,cx+rad*.43,cy-rad*.72)
    love.graphics.polygon('fill',cx+rad*.16,cy-rad*.60,cx+rad*.76,cy-rad*.48,
      cx+rad*.55,cy-rad*.01,cx+rad*.08,cy-rad*.25)
  elseif kind=='assassin' then
    love.graphics.line(cx-rad*.48,cy-rad*.70,cx-rad*.1,cy-rad*.35,
      cx+rad*.04,cy,cx-rad*.1,cy+rad*.35,cx-rad*.48,cy+rad*.70)
    love.graphics.line(cx-rad*.48,cy-rad*.70,cx-rad*.48,cy+rad*.70)
    love.graphics.line(cx-rad*.72,cy,cx+rad*.69,cy)
    love.graphics.polygon('fill',cx+rad*.77,cy,cx+rad*.36,cy-rad*.24,cx+rad*.36,cy+rad*.24)
  elseif kind=='wizard' then
    love.graphics.line(cx-rad*.4,cy+rad*.75,cx+rad*.38,cy-rad*.65)
    love.graphics.polygon('fill',cx+rad*.38,cy-rad*.94,cx+rad*.49,cy-rad*.6,
      cx+rad*.82,cy-rad*.54,cx+rad*.49,cy-rad*.41,cx+rad*.38,cy-rad*.1,
      cx+rad*.23,cy-rad*.41,cx-rad*.08,cy-rad*.54,cx+rad*.24,cy-rad*.67)
  elseif kind=='archer' then
    love.graphics.line(cx-rad*.42,cy-rad*.67,cx+rad*.28,cy-rad*.38,
      cx+rad*.42,cy,cx+rad*.28,cy+rad*.38,cx-rad*.42,cy+rad*.67,cx-rad*.42,cy-rad*.67)
    love.graphics.line(cx-rad*.68,cy,cx+rad*.74,cy)
  else -- ogre, fallback symbol
    love.graphics.polygon('line',cx-rad*.60,cy-rad*.70,cx+rad*.60,cy-rad*.70,
      cx+rad*.52,cy+rad*.25,cx,cy+rad*.84,cx-rad*.52,cy+rad*.25)
    love.graphics.line(cx,cy-rad*.49,cx,cy+rad*.48)
    love.graphics.line(cx-rad*.34,cy-rad*.04,cx+rad*.34,cy-rad*.04)
  end
end
local function healthBar(x,y,w,h,amount,maximum)
  love.graphics.setColor(0.08,0.11,0.15,1)
  love.graphics.rectangle('fill',x,y,w,h,2,2)
  if amount>0 then
    local ratio=math.max(0,math.min(1,amount/math.max(maximum,1)))
    color(ratio<0.35 and palette.red or palette.green)
    love.graphics.rectangle('fill',x,y,w*ratio,h,2,2)
  end
end
local function criticalPulse(cx,cy,rad,hp,maximum)
  if not rules.isCritical(hp,maximum) then return end
  local g=love.graphics
  local pulse=.5+.5*math.sin(animationTime*math.pi*1.6)
  local vertices=faceHex(cx,cy,rad*(1.08+.07*pulse))
  local function corners(width)
    g.setLineWidth(width)
    for i=1,11,2 do
      local previous=(i-3)%12+1
      local following=(i+1)%12+1
      local x,y=vertices[i],vertices[i+1]
      g.line(x+(vertices[previous]-x)*.43,y+(vertices[previous+1]-y)*.43,
        x,y,x+(vertices[following]-x)*.43,y+(vertices[following+1]-y)*.43)
    end
  end
  g.setColor(.15,.025,.04,.90)
  corners(math.max(3.5,rad*.22))
  g.setColor(1,.26,.18,.38+.58*pulse)
  corners(math.max(2,rad*.14))
end
local function contactShadow(cx,cy,rad)
  local g=love.graphics
  g.setColor(.025,.023,.028,.47)
  g.polygon('fill',faceHex(cx+rad*.04,cy+rad*.11,rad*.91))
end
local function unitToken(u,displayHp)
  local cx,cy=center(u.r,u.c)
  local rad=layout.radius
  local sprite=unitArt[u.owner][u.class]
  local active=selected==u.id and not moving and not overlay
  local lift=active and rad*.23*smoothstep(selectionAge/.16) or 0
  contactShadow(cx,cy,rad)
  if active then
    local g=love.graphics
    g.setColor(.085,.063,.041,.56)
    g.polygon('fill',faceHex(cx,cy+rad*.10,rad*1.09))
    g.setColor(1,.87,.56,.92)
    g.setLineWidth(math.max(1.6,rad*.085))
    g.polygon('line',faceHex(cx,cy,rad*1.05))
  end
  cy=cy-lift
  if sprite then
    drawBadgeSprite(sprite,cx,cy,layout.scale)
  else
    color(teamColors[u.owner]);love.graphics.polygon('fill',faceHex(cx,cy,rad*.99))
    color(classColors[u.class]);love.graphics.polygon('fill',faceHex(cx,cy,rad*.82))
    emblem(u.class,cx,cy,rad*.48)
  end
  -- HP is in the inspection card; a small bar appears for injuries.
  local hp=displayHp or u.hp
  if hp<rules.classes[u.class].hp then
    healthBar(cx-rad*.52,cy+rad*.90,rad*1.04,math.max(3.5,layout.cell*.06),
      hp,rules.classes[u.class].hp)
  end
end
local tileCanvas
local fieldAtlas,fieldQuads
local FIELD_CELL,FIELD_RADIUS = 160,76
local function loadFieldArt(mipmaps)
  if not love.graphics.newQuad then return end
  local g=love.graphics
  local ok,atlas=pcall(g.newImage,'art/weathered-flagstones.png',{mipmaps=mipmaps})
  if not ok then ok,atlas=pcall(g.newImage,'art/weathered-flagstones.png') end
  if not ok or not atlas then return end
  local w,h=atlas:getDimensions()
  local classic=timers.rulebook
  if w~=classic.COLS*FIELD_CELL or h~=classic.ROWS*FIELD_CELL then return end
  local quads={}
  for r=0,classic.ROWS-1 do
    for c=0,classic.rowWidths[r+1]-1 do
      quads[r*classic.COLS+c]=g.newQuad(c*FIELD_CELL,r*FIELD_CELL,FIELD_CELL,FIELD_CELL,w,h)
    end
  end
  fieldAtlas,fieldQuads=atlas,quads
end

-- Basic stone detail for hosts where the board art cannot load.
local function paintFallbackTile(g,x,y,R,r,c,engine)
  engine=engine or rules
  local seed=(r*47+c*31+13)%97
  local t=(seed%15-7)*.005
  local cold=math.max(0,1-(r+math.abs(c-(engine.rowWidths[r+1]-1)*.5)*.54)/4)
  local warm=math.max(0,1-(engine.ROWS-1-r+math.abs(c-(engine.rowWidths[r+1]-1)*.5)*.54)/4)
  g.setColor(.45+t+.065*warm-.035*cold,.418+t*.7+.018*warm+.008*cold,
    .377+t*.6-.015*warm+.058*cold,1)
  g.polygon('fill',faceHex(x,y,R*1.002))
  g.setColor(.86,.82,.73,.095)
  g.polygon('fill',x-R*.24,y-R*.67,x+R*.26,y-R*.67,
    x+R*.48,y-R*.34,x+R*.11,y-R*.39,x-R*.14,y-R*.39)
  for k=1,7 do
    local a=((seed*7+k*43)%91)/91*math.pi*2
    local dist=R*(.1+((seed+k*13)%15)/43)
    local sx,sy=x+math.cos(a)*dist,y+math.sin(a)*dist
    local q=R*(.027+((seed+k*7)%9)/170)
    if k%2==0 then g.setColor(.22,.23,.19,.20)
    else g.setColor(.94,.89,.75,.10) end
    g.polygon('fill',sx-q,sy-q*.5,sx+q*.5,sy-q*.8,
      sx+q,sy+q*.36,sx-q*.7,sy+q*.55)
  end
  if seed%3~=0 then
    local sx,sy=x+R*((seed%11-5)/22),y+R*((seed%7-3)/18)
    g.setColor(.20,.22,.19,.20)
    g.setLineWidth(math.max(.55,R*.016))
    g.line(sx-R*.13,sy-R*.06,sx-R*.02,sy+R*.055,
      sx+R*.14,sy+R*.005)
  end
end
-- Staggered flagstones with a continuous raised rim beneath the floor.
local function paintField(engine,view)
  engine,view=engine or rules,view or layout
  local g=love.graphics
  local R=view.hexR
  local edgeWidth=math.max(1.5,R*.12)
  for _,layer in ipairs({{3.6,.08,.07,.085},{2.1,.24,.20,.17},{1.2,.48,.40,.30}}) do
    g.setLineWidth(edgeWidth*layer[1])
    g.setColor(layer[2],layer[3],layer[4],1)
    for r=0,engine.ROWS-1 do
      for c=0,engine.rowWidths[r+1]-1 do
        if engine.playable(r,c) then
          local x,y=center(r,c,engine,view)
          g.polygon('line',faceHex(x,y,R))
        end
      end
    end
  end
  for r=0,engine.ROWS-1 do
    for c=0,engine.COLS-1 do
      if engine.playable(r,c) then
        local x,y=center(r,c,engine,view)
        if fieldAtlas then
          g.setColor(1,1,1,1)
          local scale=R/FIELD_RADIUS
          local row,column=r,c
          if engine.board.id~='classic' then
            row=3+r%4
            column=(c+2*r)%timers.rulebook.rowWidths[row+1]
          end
          g.draw(fieldAtlas,fieldQuads[row*timers.rulebook.COLS+column],x,y,0,scale,scale,FIELD_CELL*.5,FIELD_CELL*.5)
        else
          paintFallbackTile(g,x,y,R,r,c,engine)
        end
        g.setColor(.10,.10,.09,.93)
        g.setLineWidth(math.max(.8,math.min(1.3,R*.034)))
        g.polygon('line',faceHex(x,y,R*.996))
      end
    end
  end
end
-- The same High Keep badge appears on the board, in combat, and in the finale.
local function fortressArt(x,y,owner,R,opacity)
  local g=love.graphics
  local image=fortArt[owner]
  if image then
    drawBadgeSprite(image,x,y,R/BADGE_R,opacity)
    return
  end
  if owner==1 then g.setColor(.36,.09,.12,1)
  else g.setColor(.08,.20,.38,1) end
  g.polygon('fill',faceHex(x,y,R*.98))
  g.setColor(.10,.09,.075,.4)
  g.polygon('fill',x-R*.74,y+R*.57,x+R*.74,y+R*.57,
    x+R*.53,y+R*.69,x-R*.53,y+R*.69)
  g.setColor(.59,.57,.51,1)
  g.rectangle('fill',x-R*.56,y-R*.21,R*1.12,R*.70)
  g.setColor(.84,.79,.68,1)
  g.rectangle('fill',x-R*.54,y-R*.19,R*1.08,R*.13)
  for _,sign in ipairs({-1,1}) do
    local tx=x+sign*R*.46
    g.setColor(.37,.37,.35,1)
    g.rectangle('fill',tx-R*.23,y-R*.50,R*.46,R*1.04)
    g.setColor(.72,.70,.63,1)
    g.rectangle('fill',tx-R*.20,y-R*.47,R*.40,R*.96)
    g.setColor(.87,.83,.73,1)
    for k=-1,1 do
      g.rectangle('fill',tx+k*R*.13-R*.054,y-R*.67,R*.108,R*.24)
    end
    g.setColor(.26,.28,.29,1)
    g.rectangle('fill',tx-R*.065,y-R*.15,R*.13,R*.23)
    g.setColor(.32,.31,.28,.45)
    g.line(tx-R*.16,y+R*.08,tx+R*.16,y+R*.08)
  end
  g.setColor(.17,.16,.14,1)
  g.rectangle('fill',x-R*.17,y+R*.12,R*.34,R*.40)
  g.circle('fill',x,y+R*.12,R*.17)
  g.setColor(.95,.79,.46,1)
  g.setLineWidth(math.max(1,R*.052))
  g.line(x,y-R*.78,x,y-R*.31)
  if owner==1 then g.setColor(.86,.19,.25,1)
  else g.setColor(.27,.55,.91,1) end
  g.polygon('fill',x,y-R*.76,x+R*.33,y-R*.64,x,y-R*.49)
  g.setColor(.98,.81,.43,1)
  g.setLineWidth(math.max(1,R*.046))
  g.polygon('line',faceHex(x,y,R*.98))
end
-- Use different silhouettes for actions even when viewed in grayscale.
local function moveMarker(cx,cy,rad,item)
  local g=love.graphics
  if item then
    color(palette.gold,.97)
    g.setLineWidth(math.max(1.3,rad*.085))
    g.polygon('line',faceHex(cx,cy,rad*.90))
    return
  end
  g.setColor(.12,.096,.061,.82)
  g.circle('fill',cx,cy,math.max(5,rad*.33))
  color(palette.gold,.97)
  g.setLineWidth(math.max(1.3,rad*.09))
  g.circle('line',cx,cy,math.max(4,rad*.27))
  g.circle('fill',cx,cy,math.max(1.4,rad*.078))
end

local function targetMarker(cx,cy,rad,chosen,selectedAt)
  local g=love.graphics
  local radius=rad*1.025
  local rim=faceHex(cx,cy,radius)

  -- A steady icy rim leaves critical Health as the pulsing board cue.
  g.setColor(.42,.77,.92,chosen and .25 or .27)
  g.setLineWidth(math.max(3.4,rad*.25))
  g.polygon('line',rim)
  g.setColor(.08,.15,.21,.94)
  g.setLineWidth(math.max(2.8,rad*.18))
  g.polygon('line',rim)
  if chosen then g.setColor(.84,.97,1,1)
  else g.setColor(.66,.86,.94,1) end
  g.setLineWidth(chosen and math.max(1.8,rad*.12) or math.max(1.15,rad*.085))
  g.polygon('line',rim)

  if not chosen then
    g.setColor(.86,.97,1,.92)
    g.setLineWidth(math.max(1.35,rad*.10))
    g.line(rim[5],rim[6],rim[7],rim[8],rim[9],rim[10])
  elseif selectedAt then
    local corners=faceHex(cx,cy,rad*1.10)
    g.setColor(1,.91,.65,1)
    g.setLineWidth(math.max(1.55,rad*.115))
    for i=1,12,4 do
      local prev,next=(i-3)%12+1,(i+1)%12+1
      local x,y=corners[i],corners[i+1]
      g.line(x+(corners[prev]-x)*.28,y+(corners[prev+1]-y)*.28,
        x,y,x+(corners[next]-x)*.28,y+(corners[next+1]-y)*.28)
    end
    local elapsed=animationTime-selectedAt
    for i=0,2 do
      local phase=(elapsed-i*.14)/.62
      if phase>=0 and phase<1 then
        local ripple=rad*(.26+.765*(1-(1-phase)^1.5))
        g.setColor(.75,.94,1,.84*(1-phase^1.8))
        g.setLineWidth(math.max(1.2,rad*.085))
        g.polygon('line',faceHex(cx,cy,ripple))
      end
    end
  end
end

local function duelSkull(g,x,y,size,alpha,pulseTime)
  if alpha<=0 then return end
  if pulseTime then
    local phase=(pulseTime%2.8)/2.8
    local pulse=.5-.5*math.cos(2*math.pi*phase)
    size=size*(.94+.15*pulse)
  end
  local function stroke(points)
    local pixels={}
    for i=1,#points,2 do pixels[i],pixels[i+1]=x+points[i]*size,y+points[i+1]*size end
    g.polygon('fill',pixels)
  end
  -- Tapered shafts with paired rounded knuckles at both ends.
  for _,sign in ipairs({-1,1}) do
    local ux,uy=sign*.80,.60
    local nx,ny=-uy,ux
    local function bone(shade,shaft,knuckle)
      g.setColor(shade[1],shade[2],shade[3],alpha)
      stroke({-ux*.78+nx*shaft,-uy*.78+ny*shaft,
        ux*.78+nx*shaft,uy*.78+ny*shaft,
        ux*.78-nx*shaft,uy*.78-ny*shaft,
        -ux*.78-nx*shaft,-uy*.78-ny*shaft})
      for _,endSign in ipairs({-1,1}) do
        for _,lobe in ipairs({-1,1}) do
          local bx=endSign*ux*.78+nx*lobe*.080
          local by=endSign*uy*.78+ny*lobe*.080
          g.circle('fill',x+bx*size,y+by*size,size*knuckle)
        end
      end
    end
    bone({.30,.12,.105},.103,.126)
    bone({.81,.57,.40},.061,.101)
  end
  g.setColor(.30,.075,.092,alpha)
  g.circle('fill',x,y-size*.11,size*.57)
  stroke({-.41,.07,.41,.07,.33,.52,-.33,.52})
  g.setColor(.94,.71,.55,alpha)
  g.circle('fill',x,y-size*.14,size*.50)
  stroke({-.36,.06,.36,.06,.26,.49,-.26,.49})
  g.setColor(1,.91,.73,alpha*.70)
  stroke({-.39,-.28,-.30,-.45,-.06,-.57,.24,-.50,.31,-.37,-.11,-.43})
  g.setColor(.15,.025,.043,alpha)
  for _,sign in ipairs({-1,1}) do
    stroke({sign*.065,-.13,sign*.31,-.23,sign*.39,-.07,sign*.28,.074,sign*.11,.048})
  end
  stroke({0,-.01,-.09,.20,.09,.20})
  for i=-1,1 do
    g.rectangle('fill',x+(i*.13-.021)*size,y+size*.34,size*.042,size*.15)
  end
end

local function deathMatchMarker(cx,cy,rad,elapsed)
  local phase=((elapsed*CINEMATIC_SPEED+.16)%.82)/.82
  local fade=smoothstep(phase/.16)*(1-smoothstep((phase-.36)/.64))
  local scale=rad*(.62+.64*smoothstep(phase))
  duelSkull(love.graphics,cx,cy-rad*.19*phase,scale,fade*.94)
end

local function drawFortressDamage(x,y,rad,hp)
  if hp<=0 or hp>=rules.FORT_HP then return end
  local g=love.graphics
  local severe=hp<=rules.FORT_HP*.40
  local function line(points)
    local pixels={}
    for i=1,#points,2 do
      pixels[i],pixels[i+1]=x+points[i]*rad,y+points[i+1]*rad
    end
    g.line((table.unpack or unpack)(pixels))
  end
  -- Scars sit inside the badge and follow the tower masonry.
  g.setColor(.22,.108,.073,.91)
  g.setLineWidth(math.max(1.4,rad*.10))
  line({-.23,-.48,-.30,-.34,-.23,-.24,-.29,-.11})
  g.setColor(.98,.75,.51,.83)
  g.setLineWidth(math.max(.70,rad*.036))
  line({-.19,-.47,-.26,-.33,-.19,-.23,-.25,-.10})
  if not severe then return end
  g.setColor(.135,.085,.078,.98)
  g.polygon('fill',x+rad*.44,y-rad*.18,x+rad*.59,y-rad*.17,
    x+rad*.51,y-rad*.04,x+rad*.60,y+rad*.10,x+rad*.43,y+rad*.18,x+rad*.48,y+rad*.03)
  g.setColor(.91,.67,.42,.85)
  line({.44,-.18,.48,.03,.43,.18})
  local time=animationTime
  for i=1,4 do
    local age=(time*.58+i*.25)%1
    local px=x+rad*(.50+.22*age+math.sin(time*2+i)*.07)
    local py=y-rad*(.26+.77*age)
    g.setColor(.20,.18,.19,.68*(1-age))
    g.circle('fill',px,py,rad*(.16+.28*age))
  end
  g.setColor(.88,.30,.10,.46)
  g.circle('fill',x+rad*.51,y-rad*.04,math.max(2.0,rad*.15))
  g.setColor(1,.63,.29,.74+.20*math.sin(time*9))
  g.circle('fill',x+rad*.51,y-rad*.04,math.max(1.4,rad*.08))
end

local function prepareTileCanvas()
  if tileCanvas==nil and love.graphics.newCanvas then
    -- A broken or unsupported canvas is retried only after a resize.
    tileCanvas=false
    local g=love.graphics
    local ok,canvas=pcall(g.newCanvas,layout.w,layout.h)
    if ok and canvas then
      -- A canvas must explicitly request a stencil buffer in LÖVE 11.5.
      -- If unavailable (older browser GPU), safely render uncached below.
      local setOk=pcall(g.setCanvas,{canvas,stencil=true})
      if setOk then
        g.clear(0,0,0,0)
        g.push()
        g.origin()
        local paintOk=pcall(paintField)
        g.pop()
        g.setCanvas()
        if paintOk then tileCanvas=canvas end
      end
    end
  end
end

function timers.useBoard(id)
  local engine=timers.rulebook.forBoard(id)
  if engine==rules then return end
  rules=engine
  tileCanvas=nil
  if intro then intro.surface=nil end
  reflow(love.graphics.getDimensions())
end

function timers.drawWalls(board,engine,view)
  local g=love.graphics
  local ring=engine.board.wallRing
  for _,wall in pairs(board.walls) do
    local x,y=center(wall.r,wall.c,engine,view)
    if not ring or wall.hp<=0 then
      timers.variantUI.wall(g,x,y,view.hexR,wall.hp,board.options.wallHealth)
    end
  end
  if not ring then return end
  for i,cell in ipairs(ring) do
    local wall=board.walls[engine.key(cell[1],cell[2])]
    if wall and wall.hp>0 then
      local x,y=center(cell[1],cell[2],engine,view)
      local before,after=ring[(i-2)%#ring+1],ring[i%#ring+1]
      local ax,ay=center(before[1],before[2],engine,view)
      local bx,by=center(after[1],after[2],engine,view)
      local previous=board.walls[engine.key(before[1],before[2])]
      local following=board.walls[engine.key(after[1],after[2])]
      timers.variantUI.ringWall(g,(ax+x)/2,(ay+y)/2,x,y,(bx+x)/2,(by+y)/2,view.hexR,
        wall.hp,board.options.wallHealth,previous and previous.hp>0 or false,following and following.hp>0 or false)
    end
  end
end

function timers.drawSetupPreview(x,y,w,h)
  local setup=timers.settings
  local options=setup.options
  local engine=timers.rulebook.forBoard(options.board)
  if not setup.preview or setup.preview.boardId~=options.board or setup.preview.options.wall~=options.wall then
    setup.preview=engine.new(1,1,{wall=options.wall,legacyFlankWall=options.legacyFlankWall,
      legacyBridgeWall=options.legacyBridgeWall})
  end
  local board=setup.preview
  local wide=engine.COLS*SQRT3
  local tall=(engine.ROWS-1)*1.5+2
  local r=math.max(1,math.min((w-7)/wide,(h-7)/tall))
  local view={x=x+(w-wide*r)*.5,y=y+(h-tall*r)*.5,hexR=r,hexStepX=SQRT3*r,hexStepY=1.5*r}
  paintField(engine,view)
  timers.drawWalls(board,engine,view)
  for _,u in ipairs(board.units) do
    local cx,cy=center(u.r,u.c,engine,view)
    local sprite=unitArt[u.owner][u.class]
    if sprite then drawBadgeSprite(sprite,cx,cy,r*.93/BADGE_R)
    else
      color(teamColors[u.owner]);love.graphics.polygon('fill',faceHex(cx,cy,r*.76))
      emblem(u.class,cx,cy,r*.40)
    end
  end
  for _,keep in ipairs(board.forts) do
    local cx,cy=center(keep.r,keep.c,engine,view)
    fortressArt(cx,cy,keep.owner,r*.84)
  end
end

function timers.drawResurrectionToken(unit,view)
  local g=love.graphics
  local x,y=center(unit.r,unit.c)
  local radius=layout.radius
  local t=view.elapsed
  local morph=smoothstep((t-.32)/.55)
  local flare=math.sin(math.pi*morph)
  local gold={1,.78,.42}
  local before=unitArt[unit.owner].soldier
  local after=unitArt[unit.owner][unit.class]
  if before and morph<1 then drawBadgeSprite(before,x,y,layout.scale*(1+.13*flare),1-morph) end
  if after then drawBadgeSprite(after,x,y,layout.scale*(1+.26*flare),morph) end
  if not before or not after then unitToken(unit) end
  local rise=smoothstep(t/.22)*(1-smoothstep((t-.95)/.60))
  color(gold,.75*rise)
  g.setLineWidth(math.max(1.6,radius*.09))
  g.polygon('line',faceHex(x,y,radius*(1.05+.35*morph)))
  color({1,.92,.65},flare*.73)
  g.circle('fill',x,y,radius*(.15+.68*flare))
  for i=1,14 do
    local angle=i*2.39996+t*.8
    local spread=radius*(.28+(i%5)*.12+.55*morph)
    local px=x+math.cos(angle)*spread
    local py=y+math.sin(angle)*spread-radius*t*.46
    local light=radius*(.033+(i%3)*.014)
    color(gold,rise*(.52+(i%4)*.12))
    g.polygon('fill',px-light,py,px,py-light*1.8,px+light,py,px,py+light*1.8)
  end
end

local function drawBoard(practice,practiceMove)
  local board=practice or state
  local animation=practiceMove or moving
  prepareTileCanvas()
  if tileCanvas then
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(tileCanvas,0,0)
  else
    paintField()
  end
  if selected and not overlay and not state.winner then
    for k in pairs(targets.moves or {}) do
      local r,c=rules.fromkey(k)
      local cx,cy=center(r,c)
      moveMarker(cx,cy,layout.radius,board.crates[k] or board.potions[k])
    end
  end
  timers.drawWalls(board,rules,layout)
  local crateEvent=overlay and overlay.type=='crate' and overlay.event or queuedEvent
  local effectKey=crateEvent and crateEvent.crate and rules.key(crateEvent.to.r,crateEvent.to.c)
  for key in pairs(board.scorches) do
    if key~=effectKey or overlay and overlay.type=='crate' and overlay.elapsed>=.9 then
      local rr,c=rules.fromkey(key)
      local x,y=center(rr,c)
      timers.variantUI.scorch(love.graphics,x,y,layout.radius)
    end
  end
  for _,crate in pairs(board.crates) do
    local x,y=center(crate.r,crate.c)
    timers.variantUI.crate(love.graphics,x,y,layout.radius)
  end
  if effectKey and (queuedEvent or overlay.elapsed<.20) then
    local x,y=center(crateEvent.to.r,crateEvent.to.c)
    timers.variantUI.crate(love.graphics,x,y,layout.radius)
  end
  for _,potion in pairs(board.potions) do
    local x,y=center(potion.r,potion.c)
    local occupied=rules.occupied(board,potion.r,potion.c)
    if not occupied then timers.variantUI.potion(love.graphics,x,y,layout.radius) end
  end
  local route=intended and intended.route
  if route and not overlay and not animation then
    local g=love.graphics
    for i=2,#route do
      local from,to=route[i-1],route[i]
      local ax,ay=center(from.r,from.c)
      local bx,by=center(to.r,to.c)
      g.setColor(.105,.073,.055,.94);g.setLineWidth(4.4)
      g.line(ax,ay,bx,by)
      color(palette.gold,.97);g.setLineWidth(2)
      g.line(ax,ay,bx,by)
      g.circle('fill',bx,by,math.max(2,layout.radius*.12))
    end
  end
  for _,fort in ipairs(board.forts) do
    local cx,cy=center(fort.r,fort.c)
    local rr=layout.radius
    if selected==fort.id and not overlay then
      color(palette.gold,.94)
      love.graphics.setLineWidth(math.max(1.6,rr*.085))
      love.graphics.polygon('line',faceHex(cx,cy,rr*1.05))
    end
    if fort.hp>0 then
      contactShadow(cx,cy,rr)
      fortressArt(cx,cy,fort.owner,rr)
      drawFortressDamage(cx,cy,rr,fort.hp)
    end
    if fort.hp<rules.FORT_HP then
      healthBar(cx-rr*.58,cy+rr*.91,rr*1.16,math.max(3.5,layout.cell*.06),
        fort.hp,rules.FORT_HP)
    end
  end
  for _,u in ipairs(board.units) do
    local elapsed=not practice and overlay and overlay.event and overlay.event.id==u.id and overlay.elapsed
    local crate=elapsed and overlay.type=='crate' and overlay.event.crate
    local reveal=crate and not crate.destroyed and elapsed<.9
    local flashTime
    if elapsed and overlay.type=='trap' then flashTime=elapsed
    elseif crate and not crate.destroyed and crate.contents=='bomb' and elapsed>=.9 then flashTime=elapsed-.9 end
    local trapFlash=flashTime and flashTime<.48
    if (u.hp>0 or reveal or trapFlash) and (not animation or animation.id~=u.id) then
      if elapsed and overlay.type=='resurrection' then
        timers.drawResurrectionToken(u,overlay)
      elseif elapsed and overlay.type=='resurrectionChoice' then
        local to=overlay.event.to
        unitToken({id=u.id,r=to.r,c=to.c,owner=u.owner,class=u.class,hp=u.hp})
      else
        unitToken(u,reveal and u.hp-crate.change or nil)
      end
      if trapFlash then
        local cx,cy=center(u.r,u.c)
        local fade=1-flashTime/.48
        local g=love.graphics
        g.setColor(1,.90,.70,.84*fade)
        g.polygon('fill',faceHex(cx,cy,layout.radius*.96))
        g.setColor(1,.72,.28,fade);g.setLineWidth(3)
        g.polygon('line',faceHex(cx,cy,layout.radius))
      end
    end
  end
  for _,potion in pairs(board.potions) do
    if rules.occupied(board,potion.r,potion.c) then
      local x,y=center(potion.r,potion.c)
      timers.variantUI.potion(love.graphics,x+layout.radius*.70,y+layout.radius*.51,layout.radius*.52)
    end
  end
  if selected and not overlay and not animation then
    local crossed=intended and intended.crossed or targets.crossed
    if crossed then
      love.graphics.setColor(.79,.96,1,intended and .66 or .40)
      love.graphics.setLineWidth(math.max(1.3,layout.radius*.075))
      for k in pairs(crossed) do
        local r,c=rules.fromkey(k)
        local cx,cy=center(r,c)
        love.graphics.polygon('line',faceHex(cx,cy,layout.radius*1.06))
      end
    end
  end
  if animation then
    local unit=board.units[animation.id]
    local movingClass=animation.pieceClass or unit.class
    local sprite=unitArt[unit.owner][movingClass]
    moveFx.draw(love.graphics,animation,center,layout.radius,function(cx,cy,scale,opacity)
      if sprite then
        drawBadgeSprite(sprite,cx,cy,layout.scale*scale,opacity)
      else
        color(teamColors[unit.owner],opacity)
        love.graphics.polygon('fill',faceHex(cx,cy,layout.radius*.81*scale))
      end
      if opacity>.85 then
        local maximum=rules.classes[movingClass].hp
        local hp=animation.hpBeforeLanding or unit.hp
        criticalPulse(cx,cy,layout.radius,hp,maximum)
        if hp<maximum then
          local rad=layout.radius
          healthBar(cx-rad*.52,cy+rad*.90,rad*1.04,math.max(3.5,layout.cell*.06),hp,maximum)
        end
      end
    end)
  end
  if intended and intended.type=='move' and not overlay then
    local g=love.graphics
    local cx,cy=center(intended.r,intended.c)
    local rad=layout.radius
    local key=rules.key(intended.r,intended.c)
    local potion=board.potions[key] or board.crates[key]
    if not potion then
      g.setColor(.16,.115,.065,.90)
      g.circle('fill',cx,cy,rad*.47)
    end
    color(palette.gold)
    g.setLineWidth(math.max(1.7,rad*.12))
    g.circle('line',cx,cy,rad*(potion and .84 or .47))
    if not potion then g.line(cx-rad*.23,cy,cx-rad*.055,cy+rad*.18,cx+rad*.24,cy-rad*.18) end
  end
  if practice then return end
  local attackTargets=selected and not overlay and targets.attacks
  local function healthRadius(piece)
    -- Keep the pulsing corners inside an attack rim when both cues apply.
    local marked=attackTargets and attackTargets[rules.key(piece.r,piece.c)]
      and not (intended and intended.deathMatch and piece.r==intended.r and piece.c==intended.c)
    return layout.radius*(marked and .75 or 1)
  end
  for _,fort in ipairs(board.forts) do
    local cx,cy=center(fort.r,fort.c)
    criticalPulse(cx,cy,healthRadius(fort),fort.hp,rules.FORT_HP)
  end
  for _,u in ipairs(board.units) do
    if u.hp>0 and u.hp<=rules.classes[u.class].hp*.25 and (not animation or animation.id~=u.id) then
      local cx,cy=center(u.r,u.c)
      criticalPulse(cx,cy,healthRadius(u),u.hp,rules.classes[u.class].hp)
    end
  end
  if attackTargets then
    for key in pairs(attackTargets) do
      local r,c=rules.fromkey(key)
      local cx,cy=center(r,c)
      local chosen=intended and (intended.type=='attack' or intended.type=='potion' or intended.type=='crate') and intended.r==r and intended.c==c
      if not (chosen and intended.deathMatch) then
        targetMarker(cx,cy,layout.radius,chosen,chosen and intended.selectedAt)
      end
    end
  end
  if attackTargets and intended and intended.deathMatch then
    local cx,cy=center(intended.r,intended.c)
    deathMatchMarker(cx,cy,layout.radius,math.max(0,animationTime-intended.selectedAt))
  end
end
local function drawPortrait(sprite,x,y,w,h)
  local g=love.graphics
  local clipped=g.stencil and g.setStencilTest
  if clipped then
    g.stencil(function() g.rectangle('fill',x,y,w,h,9,9) end,'replace',1)
    g.setStencilTest('greater',0)
  end
  local iw,ih=sprite:getDimensions()
  local scale=math.max(w/iw,h/ih)
  g.setColor(1,1,1,1)
  if clipped then
    g.draw(sprite,x+(w-iw*scale)*.5,y+(h-ih*scale)*.5,0,scale,scale)
    g.setStencilTest()
  else
    g.draw(sprite,x,y,0,w/iw,h/ih)
  end
end

-- Compact inspection card. Name, Health and stats come
-- from the same live rules state used for combat and saved sessions.
local detail=require("piece_detail")
local function drawCard(practicePiece,focus)
  cardBox=nil
  if not state then return end
  if not practicePiece and (inspected=='potion' or inspected=='crate') then
    local crate=inspected=='crate'
    local item=crate and state.crates[timers.inspectedPotion] or state.potions[timers.inspectedPotion]
    if not item then return end
    local g=love.graphics
    local x,y,w,h=4,layout.cardY,layout.w-8,layout.cardH
    cardBox={x=x,y=y,w=w,h=h}
    g.setColor(.055,.075,.105,.98);g.rectangle('fill',x,y,w,h,11,11)
    frame(x+1,y+1,w-2,h-2,.94,11)
    local icon=crate and timers.variantUI.crate or timers.variantUI.potion
    icon(g,x+w*.15,y+h*(crate and .5 or .54),math.min(w*.10,h*.40))
    local narrow=w<172
    local left=x+w*(narrow and .28 or .31)
    local textW=x+w-4-left
    color(palette.gold);g.setFont(narrow and fonts.small or fonts.medium)
    g.printf(crate and 'Mystery Crate' or 'Health Potion',left,y+h*.10,textW,'left')
    color(palette.text);g.setFont(narrow and fonts.small or fonts.stat)
    g.printf(crate and 'A potion or a bomb?\nOpen it to find out.' or 'Restores 3–8 Health',
      left,y+h*(narrow and .32 or .48),textW,'left')
    return
  end
  if not practicePiece and inspected=='wall' then
    local wall=state.walls[timers.inspectedWall]
    if not wall or wall.hp<=0 then return end
    local g=love.graphics
    local x,y,w,h=4,layout.cardY,layout.w-8,layout.cardH
    cardBox={x=x,y=y,w=w,h=h}
    g.setColor(.055,.075,.105,.98);g.rectangle('fill',x,y,w,h,11,11)
    frame(x+1,y+1,w-2,h-2,.94,11)
    timers.variantUI.wall(g,x+w*.15,y+h*.52,math.min(w*.13,h*.43),wall.hp,state.options.wallHealth)
    color(palette.gold);g.setFont(fonts.medium)
    local left=x+w*.31
    g.printf(intended and 'Wall Section · Target' or 'Wall Section',left,y+h*.10,w*.66,'left')
    color(palette.text);g.setFont(fonts.stat)
    g.printf(('Health %d / %d    ·    Shield %d'):format(wall.hp,state.options.wallHealth,wall.shield),
      left,y+h*.46,w*.66,'left')
    return
  end
  local fort=not practicePiece and inspected=='fort' and state.forts[inspectedFortOwner]
  local piece=practicePiece or fort or state.units[inspected or selected]
  if not piece or (not fort and piece.hp<=0) then return end
  local class=rules.classes[piece.class]
  local hint
  if piece.class=='fortress' then hint=piece.armed and 'Armed: fires ahead or beside' or 'Dormant: arms when attacked'
  elseif class.attackStraight then hint=class.straight and 'Move and attack straight' or 'Attacks in a straight line'
  elseif class.straight then hint='Move in a clear straight line'
  elseif class.forward then hint='Forward · Sideways on enemy back row'
  elseif piece.class=='wizard' then hint='Teleports over pieces'
  elseif piece.class=='barbarian' or piece.class=='ogre' then hint='Attacks adjacent enemies' end
  local h=layout.cardH
  local x,w=4,layout.w-8
  local y=layout.cardY
  cardBox={x=x,y=y,w=w,h=h}
  local g=love.graphics
  -- Exactly the restrained navy/charcoal/gold palette used by the game.
  g.setColor(.055,.075,.105,.98)
  g.rectangle('fill',x,y,w,h,11,11)
  local portraitW=math.min(h*.83,w*.33)
  local divider=x+portraitW
  local left=divider+9
  local avail=math.max(5,x+w-left-10)
  local team=piece.owner
  local bust=piece.class=='fortress' and fortArt[team] or portraitArt[team][piece.class] or unitArt[team][piece.class]
  if bust then
    drawPortrait(bust,x+1,y+1,portraitW+6,h-2)
  elseif fort then
    fortressArt(x+portraitW*.5,y+h*.5,team,portraitW*.43)
  end
  -- The square edge of this panel covers the portrait's inner rounded corners.
  g.setColor(.055,.075,.105,1)
  g.rectangle('fill',divider,y+1,10,h-2)
  g.setColor(.77,.62,.39,1)
  g.setLineWidth(math.max(1.35,w*.0044))
  g.line(divider,y+1,divider,y+h-1)
  frame(x+1,y+1,w-2,h-2,.94,11)
  local isTarget=not practicePiece and intended and intended.type=='attack'
  local deathMatch=isTarget and intended.deathMatch
  if deathMatch then hint='DEATH MATCH' end
  local highlightShield=isTarget and not deathMatch
  if isTarget then
    local labelH=fontHeight(fonts.cardHint)+6
    local labelX,labelY=x+6,y+h-labelH-5
    local labelW=portraitW-11
    g.setColor(.22,.075,.09,.96)
    g.rectangle('fill',labelX,labelY,labelW,labelH,4,4)
    g.setColor(.99,.84,.59,1)
    g.setFont(fonts.cardHint)
    g.printf('Target',labelX,labelY+3,labelW,'center')
  end
  local teamName=team==1 and 'RED ' or 'BLUE '
  g.setFont(fonts.medium)
  local title=teamName..class.name:upper()
  local tt=team==1 and {.93,.48,.47} or {.59,.77,.96}
  g.setColor(tt[1],tt[2],tt[3],1)
  local titleSpace=avail
  if focus=='expand' or (not practicePiece and not overlay and not moving and not state.winner) then
    cardBox.expand=detail.button(g,x+w-40,y+6,animationTime)
    cardBox.piece=piece
    titleSpace=avail-37
  end
  color(tt)
  local titleWidth=fonts.medium.getWidth and fonts.medium:getWidth(title) or avail
  if titleWidth>titleSpace and g.push and g.scale then
    local fit=titleSpace/titleWidth
    g.push();g.translate(left,y+4);g.scale(fit,fit)
    g.printf(title,0,0,avail/fit,'left');g.pop()
  else g.printf(title,left,y+4,avail,'left') end
  local function statFocus(key,sx,sy,sw,sh)
    if focus~=key and not (highlightShield and key=='shield') then return end
    g.setColor(.34,.24,.105,1)
    g.rectangle('fill',sx,sy,sw,sh,4,4)
    color(palette.gold,.95);g.setLineWidth(1.2)
    g.rectangle('line',sx,sy,sw,sh,4,4)
  end
  local function fact(label,value,fx,fy,fw,numberFont,highlighted)
    local labelH,numberH=fontHeight(fonts.cardLabel),fontHeight(numberFont)
    g.setFont(fonts.cardLabel)
    g.setColor(.73,.77,.81,1)
    g.printf(label,fx,fy+(numberH-labelH)*.5,fw,'left')
    g.setFont(numberFont)
    if highlighted then color(palette.gold) else color(palette.text) end
    g.printf(tostring(value),fx,fy,fw,'right')
  end
  local hpY=y+6+fontHeight(fonts.medium)
  local hpH=fontHeight(fonts.stat)
  statFocus('health',left-3,hpY-1,avail+5,hpH+9)
  fact('HEALTH',('%d / %d'):format(piece.hp,class.hp),left,hpY,avail,fonts.stat,true)
  healthBar(left,hpY+hpH+3,avail,3,piece.hp,class.hp)
  local bandH=layout.statBandH
  local bandY=hpY+hpH+8
  local bandX,bandW=left-3,avail+5
  g.setColor(.093,.132,.164,1)
  g.rectangle('fill',bandX,bandY,bandW,bandH,6,6)
  g.setColor(.55,.45,.31,.80)
  g.setLineWidth(1)
  g.rectangle('line',bandX,bandY,bandW,bandH,6,6)
  local rowH=fontHeight(fonts.cardStat)
  local firstY=bandY+layout.statPadding
  local secondY=firstY+rowH+4
  local cellW=bandW/layout.statColumns
  g.setColor(.60,.51,.36,.33)
  if layout.statColumns==2 then g.line(bandX+4,secondY-2,bandX+bandW-4,secondY-2) end
  for col=1,layout.statColumns-1 do
    local split=bandX+cellW*col
    g.line(split,bandY+4,split,bandY+bandH-4)
  end
  local function stat(key,label,value,col,sy)
    local sx=bandX+col*cellW
    statFocus(key,sx+2,sy-2,cellW-4,rowH+4)
    local valueText=tostring(value)
    local labelFont,valueFont=fonts.cardLabel,fonts.cardStat
    local labelW=labelFont.getWidth and labelFont:getWidth(label) or #label*fontHeight(labelFont)*.58
    local valueW=valueFont.getWidth and valueFont:getWidth(valueText) or #valueText*rowH*.62
    local gap=math.max(4,cellW*.055)
    local pairW=labelW+gap+valueW
    local scale=math.min(1,(cellW-8)/pairW)
    local start=sx+(cellW-pairW*scale)*.5
    local scaled=g.push and g.translate and g.scale
    if scaled then
      g.push();g.translate(start,sy+(rowH-rowH*scale)*.5);g.scale(scale,scale)
    end
    local tx,ty=start,sy
    if scaled then tx,ty=0,0 end
    g.setFont(labelFont)
    g.setColor(.73,.77,.81,1)
    g.printf(label,tx,ty+(rowH-fontHeight(labelFont))*.5,labelW+2,'left')
    g.setFont(valueFont)
    if focus==key or (highlightShield and key=='shield') then color(palette.gold)
    else color(palette.text) end
    g.printf(valueText,tx+labelW+gap,ty,valueW+2,'left')
    if scaled then g.pop() end
  end
  stat('power','POWER',class.power,0,firstY)
  stat('range','RANGE',rules.attackRange(piece.class),1,firstY)
  local wide=layout.statColumns==4
  stat('move','MOVE',class.move or 'ANY',wide and 2 or 0,wide and firstY or secondY)
  stat('shield','SHIELD',class.shield,wide and 3 or 1,wide and firstY or secondY)
  if hint then
    g.setFont(fonts.cardHint)
    if deathMatch then g.setColor(1,.67,.56,1) else g.setColor(.71,.76,.78,1) end
    local measured=fonts.cardHint.getWidth and fonts.cardHint:getWidth(hint) or 0
    if class.forward and not deathMatch and measured>avail and g.push and g.translate and g.scale then
      local scale=avail/(measured+1)
      g.push();g.translate(left,bandY+bandH+3);g.scale(scale,scale)
      g.printf(hint,0,0,measured+1,'left')
      g.pop()
    else
      g.printf(hint,left,bandY+bandH+3,avail,'left')
    end
  end
end

local function panel(x,y,w,h)
  local g=love.graphics
  g.setColor(.046,.059,.080,.98)
  g.rectangle('fill',x,y,w,h,12,12)
  frame(x+1,y+1,w-2,h-2,1,11)
end
local COMBAT_READY_TIME, QUICK_READY_TIME = 1.15, .24
local COLLAPSE_TIME = .75
local WINDUP, IMPACT, RESULT = 1.10, 2.00, 3.04
local RESULT_GLIDE, REWARD_FADE = .38, .44
local BONUS_LEAD, BONUS_TIME, BONUS_HOLD = .98, 3.10, .46
local REWARD_REVEAL, AUTO_REWARD = 1.04, 2.72
local DUEL_INTRO, DUEL_ROUND = 1.34, 4.20
local DUEL_SECOND, DUEL_LAND, DUEL_REVEAL = 1.73, 1.16, 3.18
local weaponLaunch={archer='loose-arrow',wizard='cast',fortress='boulder-launch'}
local function playDuelCues(view,before)
  local event=view.event
  local duel=event.deathMatch
  local after=view.elapsed
  crossedCue(before,after,.03,'duel')
  local first=math.max(1,math.floor((before-DUEL_INTRO)/DUEL_ROUND)+1)
  local last=math.min(#duel.rounds,math.floor((after-DUEL_INTRO)/DUEL_ROUND)+1)
  for i=first,last do
    local start=DUEL_INTRO+(i-1)*DUEL_ROUND
    crossedCue(before,after,start+.035,'dice-roll')
    crossedCue(before,after,start+DUEL_LAND,'land')
    crossedCue(before,after,start+DUEL_SECOND+.035,'dice-roll')
    crossedCue(before,after,start+DUEL_SECOND+DUEL_LAND,'land')
    if i==#duel.rounds then
      local attackerWins=duel.winner==1
      local winner=attackerWins and event.attackerClass or event.defenderClass
      local loser=attackerWins and event.defenderClass or event.attackerClass
      local hit=start+DUEL_REVEAL
      crossedCue(before,after,hit-.12,weaponLaunch[winner] or 'swing')
      if before<hit and after>=hit and after-hit<=.30 then
        playCue(winner)
        playHurt(loser)
      end
      crossedCue(before,after,hit+.24,loser=='fortress' and 'collapse' or 'defeat')
    else crossedCue(before,after,start+DUEL_REVEAL,'roll-tie') end
  end
end
local function battleLead(view)
  return view.quick and QUICK_READY_TIME or COMBAT_READY_TIME
end
local function newlyCritical(event)
  if event.wallHealth then return false end
  local threshold=rules.classes[event.defenderClass].hp*.25
  return event.landed and event.defenderHpStart>threshold
    and event.defenderHpEnd>0 and event.defenderHpEnd<=threshold
end
local function playBattleCues(view,before)
  local lead=battleLead(view)
  local after=view.elapsed
  local event=view.event
  local beat=lead+IMPACT
  crossedCue(before,after,lead+.04,'dice-roll')
  crossedCue(before,after,lead+WINDUP,'land')
  if event.landed or weaponLaunch[event.attackerClass] then
    local launch=weaponLaunch[event.attackerClass]
    crossedCue(before,after,lead+(launch and 1.66 or 1.70),launch or 'swing')
  end
  if before<beat and after>=beat and after-beat<=.30 then
    playCue(event.landed and event.attackerClass or 'blocked')
    if event.landed then playHurt(event.defenderClass) end
    if event.firstFortHit then playCue('breach')
    elseif newlyCritical(event) then playCue('critical') end
  end
  if event.defeated and event.defenderClass~='fortress' then
    crossedCue(before,after,beat+.47,event.wallHealth and 'collapse' or 'defeat')
  end
  local reveal=lead+RESULT+REWARD_REVEAL+REWARD_FADE*.8
  if event.fullHealth then crossedCue(before,after,reveal,'full-health')
  elseif event.heal then crossedCue(before,after,reveal,'reward-ready') end
end
local function playRewardCues(before,after)
  crossedCue(before,after,BONUS_LEAD+.10,'dice-roll')
  crossedCue(before,after,BONUS_TIME,'land')
  crossedCue(before,after,BONUS_TIME+.14,'heal')
end
local function playerControlsReward(actor)
  return mode=='local' or mode=='solo' and actor==1 or mode=='online' and actor==onlineSide
end
-- Readable graybox figures until finished character art is ready.
-- Different silhouettes and visible weapons make the fighters identifiable by class.
local function drawBattleFigure(kind,cx,cy,r)
  local function poly(points) love.graphics.polygon('fill',(table.unpack or unpack)(points)) end
  local function line(points,width)
    love.graphics.setLineWidth(width or r*.11)
    love.graphics.line((table.unpack or unpack)(points))
  end
  local armor={
    warrior={.33,.62,.68},barbarian={.66,.39,.25},archer={.33,.58,.33},
    wizard={.50,.40,.78},knight={.71,.78,.85},
  }
  color(armor[kind] or palette.top)
  poly({cx-r*.48,cy+r*.68,cx-r*.34,cy+r*.04,cx+r*.34,cy+r*.04,cx+r*.48,cy+r*.68})
  love.graphics.setColor(.95,.77,.61,1)
  love.graphics.circle('fill',cx,cy-r*.30,r*.245)
  -- The helmet/hood is a class-specific silhouette, not a tiny text abbreviation.
  if kind=='wizard' then
    love.graphics.setColor(.35,.22,.61,1)
    poly({cx-r*.42,cy-r*.46,cx+r*.45,cy-r*.46,cx+r*.07,cy-r*1.02})
    love.graphics.rectangle('fill',cx-r*.48,cy-r*.5,r*.96,r*.12)
    love.graphics.setColor(.86,.76,.44,1)
    line({cx+r*.45,cy+r*.46,cx+r*.45,cy-r*.55},r*.095)
    love.graphics.circle('fill',cx+r*.45,cy-r*.65,r*.16)
  elseif kind=='assassin' then
    love.graphics.setColor(.15,.34,.23,1)
    poly({cx-r*.31,cy-r*.58,cx-r*.05,cy-r*.83,cx+r*.28,cy-r*.58,cx+r*.31,cy-r*.25,
      cx+r*.18,cy-r*.48,cx-r*.18,cy-r*.48,cx-r*.32,cy-r*.25})
    love.graphics.setColor(.92,.80,.52,1)
    line({cx+r*.48,cy-r*.69,cx+r*.79,cy-r*.29,cx+r*.82,cy+r*.33,cx+r*.49,cy+r*.74},r*.085)
    line({cx+r*.48,cy-r*.69,cx+r*.49,cy+r*.74},r*.043)
    line({cx+r*.27,cy,cx+r*.98,cy},r*.065)
  elseif kind=='barbarian' then
    love.graphics.setColor(.36,.23,.15,1)
    poly({cx-r*.26,cy-r*.50,cx+r*.26,cy-r*.50,cx+r*.32,cy-r*.27,cx-r*.32,cy-r*.27})
    love.graphics.setColor(.84,.82,.67,1)
    poly({cx-r*.26,cy-r*.52,cx-r*.63,cy-r*.82,cx-r*.48,cy-r*.32})
    poly({cx+r*.26,cy-r*.52,cx+r*.63,cy-r*.82,cx+r*.48,cy-r*.32})
    love.graphics.setColor(.76,.78,.83,1)
    line({cx+r*.46,cy+r*.52,cx+r*.63,cy-r*.52},r*.105)
    poly({cx+r*.40,cy-r*.61,cx+r*.87,cy-r*.68,cx+r*.87,cy-r*.27,cx+r*.52,cy-r*.24})
  elseif kind=='knight' then
    love.graphics.setColor(.79,.84,.88,1)
    poly({cx-r*.30,cy-r*.54,cx+r*.30,cy-r*.54,cx+r*.31,cy-r*.16,cx-r*.31,cy-r*.16})
    love.graphics.setColor(.17,.25,.35,1)
    love.graphics.rectangle('fill',cx-r*.22,cy-r*.28,r*.44,r*.075)
    love.graphics.setColor(.88,.89,.94,1)
    line({cx+r*.50,cy+r*.58,cx+r*.77,cy-r*.68},r*.11)
    love.graphics.setColor(.73,.19,.22,1)
    poly({cx-r*.57,cy+r*.02,cx-r*.25,cy+r*.03,cx-r*.27,cy+r*.55,cx-r*.43,cy+r*.78,cx-r*.58,cy+r*.50})
  else -- Warrior with sword and shield
    love.graphics.setColor(.60,.68,.77,1)
    poly({cx-r*.27,cy-r*.54,cx+r*.27,cy-r*.54,cx+r*.32,cy-r*.31,cx-r*.32,cy-r*.31})
    love.graphics.setColor(.17,.24,.32,1)
    love.graphics.rectangle('fill',cx-r*.20,cy-r*.31,r*.40,r*.072)
    love.graphics.setColor(.89,.89,.90,1)
    line({cx+r*.47,cy+r*.66,cx+r*.81,cy-r*.67},r*.105)
    love.graphics.setColor(.70,.31,.28,1)
    poly({cx-r*.64,cy-r*.02,cx-r*.25,cy-r*.02,cx-r*.34,cy+r*.64,cx-r*.48,cy+r*.79,cx-r*.64,cy+r*.59})
  end
end
local function drawCombatant(kind,cx,cy,rad,team,impact)
  -- Show the FULL class art, without cropping the six corners into a circle.
  local sprite=unitArt[team] and unitArt[team][kind]
  if impact then
    love.graphics.setColor(.98,.34,.22,.18)
    love.graphics.circle('fill',cx,cy,rad*.92)
  end
  if sprite then
    drawBadgeSprite(sprite,cx,cy,rad/BADGE_R)
  else
    drawBattleFigure(kind,cx,cy,rad)
  end
end
local function drawCliffKeep(side,x,base,size,tilt,opacity,direction)
  local g=love.graphics
  local keep=siegeKeeps[side]
  if not keep then
    fortressArt(x,base-size*.45,side,size*.50,opacity)
    if direction then return x+direction*size*.06,base-size*.71 end
    return
  end
  local iw,ih=keep:getDimensions()
  g.setColor(.047,.041,.038,.48*opacity)
  if g.ellipse then g.ellipse('fill',x,base,size*.40,size*.039)
  else g.rectangle('fill',x-size*.36,base-size*.025,size*.72,size*.055,5,5) end
  g.setColor(1,1,1,opacity)
  g.draw(keep,x,base,tilt,size/iw,size/iw,iw*.5,ih)
  if direction then return x+direction*size*.10,base-size*.74 end
end

local function drawFighter(kind,team,cx,baseY,w,h,direction,strike,recoil,hp,alpha,maxHp,released)
  if kind=='wall' then
    timers.variantUI.wall(love.graphics,cx,baseY-h*.34,math.min(w,h)*.48,hp or 0,maxHp or 50,alpha)
    return
  end
  if kind=='fortress' then
    local size=math.min(w*.96,h)
    local x=cx-direction*size*.038*recoil
    local launchX,launchY=drawCliffKeep(team,x,baseY,size,0,alpha or 1,direction)
    if not alpha or alpha>.8 then
      drawFortressDamage(x,baseY-size*.42,size*.49,math.max(1,hp or rules.FORT_HP))
    end
    return launchX,launchY
  end
  local sprite=fighterArt[team][kind]
  if not sprite then
    drawCombatant(kind,cx,baseY-h*.46,math.min(w,h)*.49,team,recoil>0)
    return cx+direction*w*.22,baseY-h*.62
  end
  if kind=='archer' and released then sprite=timers.projectiles.releasedArchers[team] or sprite end
  local g=love.graphics
  local iw,ih=sprite:getDimensions()
  local scale=math.min(w/iw,h/ih)
  local lunge=(kind=='archer' or kind=='wizard') and 0 or strike
  local shift=w*(lunge*.23-recoil*.055)
  g.setColor(1,1-recoil*.20,1-recoil*.21,alpha or 1)
  -- Both teams' source art faces right. Mirror the right fighter around
  -- the waist so either team faces inward and the weapon swings with the body.
  g.draw(sprite,cx+direction*shift,baseY-h*lunge*.035,
    direction*(lunge*.12-recoil*.07),scale*direction,scale,iw*.5,ih)
  if kind=='wizard' then
    local gemX,gemY=iw*.91,ih*(team==1 and .201 or .219)
    return cx+direction*(shift+(gemX-iw*.5)*scale),baseY+(gemY-ih)*scale
  elseif kind=='archer' then
    return cx+direction*(shift+iw*.481*scale),baseY+(143-ih)*scale,iw*.56*scale
  end
end
local function drawFallenFighter(kind,team,x,base,w,h,direction,hp,age,maxHp)
  local g=love.graphics
  local fall=smoothstep((age-.09)/.74)
  if fall>=.99 then return end
  x=x-direction*w*.27*fall
  base=base+h*.18*fall
  local tilt=g.push and g.translate and g.rotate
  if tilt then
    g.push();g.translate(x,base);g.rotate(-direction*fall*1.34)
    x,base=0,0
  end
  drawFighter(kind,team,x,base,w,h,direction,0,(1-fall)*.65,hp,
    1-smoothstep((fall-.28)/.72),maxHp)
  if tilt then g.pop() end
end

local function drawDefeatSkull(cx,cy,size,age,opacity)
  if age<0 then return end
  local g=love.graphics
  local burst=math.min(1,age/.85)
  if burst<1 then
    for i=1,21 do
      local angle=i*2.39996
      local reach=size*(.24+burst)*(.62+i%4*.23)
      local x,y=cx+math.cos(angle)*reach,cy+math.sin(angle)*reach+burst*burst*size*.43
      local spark=(.04+i%5*.016)*(1-burst)*size
      g.setColor(1,i%4==0 and .76 or .35,.29,(1-burst)*.79)
      g.polygon('fill',x-spark,y,x,y-spark*2,x+spark,y,x,y+spark)
    end
  end
  local flare=math.max(0,1-age/.24)
  if flare>0 then
    g.setColor(1,.37,.31,flare*.65);g.setLineWidth(2)
    g.circle('line',cx,cy,size*(.35+1.40*(1-flare)))
  end
  local rise=smoothstep((age-.22)/.43)
  duelSkull(g,cx,cy+size*.43*(1-rise),size*(.88+.12*rise),
    rise*.93*(opacity or 1),animationTime)
end

local function drawBattleShot(kind,fromX,toX,y,size,phase,targetY,arrowLength)
  if kind=='wizard' and phase>=1.32 and phase<1.82 then
    local charge=smoothstep((phase-1.32)/.34)*(1-smoothstep((phase-1.66)/.16))
    timers.projectiles.charge(love.graphics,fromX,y,size,charge)
  end
  if phase<1.66 or phase>2.24 then return end
  local progress=math.min(1,(phase-1.66)/.34)
  local direction=toX>fromX and 1 or -1
  local dx=toX-fromX
  local g=love.graphics
  local loft=kind=='fortress' and size*3.1 or kind=='wizard' and size*.8 or 0
  local function flight(p)
    return fromX+dx*p,y+((targetY or y)-y)*p-math.sin(p*math.pi)*loft
  end
  local x,cy=flight(progress)
  local fade=math.min(1,(2.24-phase)/.24)
  if kind=='fortress' then
    local emerging=smoothstep(progress/.18)
    size=size*1.64*(.24+.76*emerging)
    local dust=smoothstep(progress/.045)*(1-smoothstep(progress/.42))
    for i=1,6 do
      local offset=(i-3.5)*size*.27
      g.setColor(.71,.61,.47,dust*(.17+i%3*.073))
      g.circle('fill',fromX+direction*offset,y-size*.39+size*(i%3)*.21,size*(.20+i%3*.10))
    end
    for i=1,6 do
      local tx,ty=flight(math.max(0,progress-i*.065))
      g.setColor(.68,.56,.43,fade*.24*(1-i/7))
      g.circle('fill',tx,ty,size*(.33+i*.11))
    end
    local rotation=progress*5.4*direction
    local outline={}
    local radii={.91,1.00,1.05,.98,.91,.97,1.02,1.02,.94,1.04,1.01,.96}
    for i,rad in ipairs(radii) do
      local a=rotation+i*math.pi*2/#radii
      outline[#outline+1]=x+math.cos(a)*size*rad
      outline[#outline+1]=cy+math.sin(a)*size*rad*.88
    end
    g.setColor(.12,.10,.085,fade)
    g.polygon('fill',outline)
    local coreX=x+math.cos(rotation-1.1)*size*.24
    local coreY=cy+math.sin(rotation-1.1)*size*.22
    for i=1,#radii do
      local j=(i-1)*2+1
      local k=(i%#radii)*2+1
      local light=.32+.15*math.cos(rotation+i*math.pi*2/#radii+2.2)+(i%3)*.038
      g.setColor(light*1.12,light,light*.87,fade)
      g.polygon('fill',coreX,coreY,outline[j],outline[j+1],outline[k],outline[k+1])
    end
    g.setColor(.77,.64,.49,fade*.55);g.setLineWidth(math.max(1,size*.067))
    g.line(coreX,coreY,coreX-size*.28,coreY+size*.20,coreX-size*.41,coreY+size*.02)
  elseif kind=='wizard' then
    for i=7,1,-1 do
      local tx,ty=flight(math.max(0,progress-i*.047))
      g.setColor(1,.20+i*.028,.045,fade*(8-i)*.059)
      g.circle('fill',tx,ty,size*(.92+i*.07))
    end
    g.setColor(1,.35,.08,.32*fade);g.circle('fill',x,cy,size*1.58)
    g.setColor(1,.48,.07,fade);g.circle('fill',x,cy,size)
    g.setColor(1,.87,.45,fade);g.circle('fill',x+direction*size*.17,cy,size*.55)
    g.setColor(1,.99,.75,fade);g.circle('fill',x+direction*size*.24,cy-size*.13,size*.25)
  elseif progress<1 then
    local angleY=(targetY or y)-y
    local length=arrowLength or size*4
    timers.projectiles.arrow(g,x,cy,dx,angleY,length,1)
  end
end
local function strikePulse(phase,rise,peak,fall)
  local t=math.max(0,math.min(1,(phase-rise)/(peak-rise),(fall-phase)/(fall-peak)))
  return t*t*(3-2*t)
end
-- Use require('d12') here to restore the previous die finish.
local drawD12=require('d12_polished')

local function luxeButton(label,x,y,w,h,red,alpha)
  local g=love.graphics
  alpha=alpha or 1
  g.setColor(.012,.013,.020,.72*alpha)
  g.rectangle('fill',x-1,y+3,w+2,h,10,10)
  if red=='neutral' then g.setColor(.14,.18,.23,alpha)
  elseif red then g.setColor(.36,.10,.14,alpha)
  else g.setColor(.08,.30,.22,alpha) end
  g.rectangle('fill',x,y,w,h,9,9)
  frame(x+.7,y+.7,w-1.4,h-1.4,(red=='neutral' and .60 or .95)*alpha,9)
  local font=fonts.large
  local tw=font.getWidth and font:getWidth(label) or #label*19
  local fh=fontHeight(font)
  local padding=math.min(18,w*.28)
  local factor=math.min(1,(w-padding)/math.max(1,tw),(h-12)/fh)
  g.setColor(1,1,.94,alpha);g.setFont(font)
  if g.push and g.translate and g.scale then
    g.push();g.translate(x+w*.5,y+h*.51);g.scale(factor,factor)
    g.printf(label,-w*.5/factor,-fh*.51,w/factor,'center')
    g.pop()
  else
    g.setFont(fonts.small)
    g.printf(label,x+5,y+h*.22,w-10,'center')
  end
end
local function battleBar(cx,y,w,amount,maxhp)
  local g=love.graphics
  local x=cx-w*.5
  local ratio=math.max(0,math.min(1,amount/maxhp))
  g.setColor(.037,.054,.073,1)
  g.rectangle('fill',x,y,w,8,4,4)
  if ratio>0 then
    if ratio<=.28 then g.setColor(.88,.27,.27,1)
    else g.setColor(.34,.76,.51,1) end
    local fill=(w-4)*ratio
    g.rectangle('fill',x+2,y+2,fill,4,2,2)
    g.setColor(1,1,.90,.26)
    g.rectangle('fill',x+2,y+2,fill,1)
  end
  g.setColor(.65,.61,.54,.70);g.setLineWidth(1)
  g.rectangle('line',x,y,w,8,4,4)
end

-- The combat and bonus dice are already resolved by rules.apply.
-- Playback reveals the same results in every mode.
local function combatTitle(label,cx,y,w,tint,scale,font,alpha,bold,angle)
  local g=love.graphics
  font=font or fonts.large
  local measured=font.getWidth and font:getWidth(label) or #label*fontHeight(font)*.59
  local fit=math.min(scale or 1,(w-8)/math.max(1,measured))
  g.setFont(font)
  if g.push and g.translate and g.scale then
    g.push();g.translate(cx,y)
    if angle and g.rotate then g.rotate(angle) end
    g.scale(fit,fit)
    if g.shear then g.shear(-.12,0) end
    local width=w/fit
    g.setColor(.15,.035,.055,alpha or 1)
    g.printf(label,-width/2+1.5,3,width,'center')
    color(tint,alpha)
    if bold then
      local offset=fontHeight(font)*.018
      g.printf(label,-width/2-offset,0,width,'center')
      g.printf(label,-width/2+offset,offset,width,'center')
    end
    g.printf(label,-width/2,0,width,'center')
    g.pop()
  else
    color(tint,alpha);g.printf(label,cx-w/2,y,w,'center')
  end
end

local function battleBackdrop(w,h,actor,footerY)
  local g=love.graphics
  g.setColor(.050,.052,.070,1)
  g.rectangle('fill',0,0,w,h)
  if arena then
    local aw,ah=arena:getDimensions()
    g.setColor(1,1,1,1)
    g.draw(arena,5,5,0,(w-10)/aw,(h-10)/ah)
  end
  for side=1,2 do
    local owner=side==1 and actor or 3-actor
    local tint=teamLabels[owner]
    for ring=6,1,-1 do
      g.setColor(tint[1]*.46,tint[2]*.32,tint[3]*.40,.035)
      g.circle('fill',w*(side==1 and .24 or .76),h*.365,w*(.175+ring*.022))
    end
  end
  local rail=footerY or h*.585
  -- Keep the arena visible through the lower controls.
  for band=0,15 do
    local y=rail+math.floor(band*(h-rail-6)/16)
    local bottom=rail+math.floor((band+1)*(h-rail-6)/16)
    g.setColor(.048,.051,.069,.28+band*.025)
    g.rectangle('fill',6,y,w-12,bottom-y)
  end
  color(palette.gold,.21);g.setLineWidth(1)
  g.line(w*.10,rail,w*.90,rail)
  frame(4,4,w-8,h-8,.95)
end

local function drawBattleOverlay(view,practice)
  local g=love.graphics
  local w,h=layout.w,layout.h
  local event=view.event
  local elapsed=view.elapsed-battleLead(view)
  local ready=elapsed<0
  local revealed=elapsed>=WINDUP
  local resolved=elapsed>=IMPACT
  local impact=event.landed and resolved
  local result=elapsed>=RESULT
  local resultAge=elapsed-RESULT
  local transfer=smoothstep(resultAge/RESULT_GLIDE)
  local rewardMix=(event.fullHealth or event.heal) and smoothstep((resultAge-REWARD_REVEAL)/REWARD_FADE) or 0
  local bonus=view.bonusElapsed
  local bonusDone=bonus and bonus>=BONUS_TIME
  local playerAttacks=practice or playerControlsReward(event.actor)
  local attacker=rules.classes[event.attackerClass]
  local defender=event.wallHealth and {name='Wall Section',hp=event.wallHealth}
    or rules.classes[event.defenderClass]
  local teamName=event.actor==1 and 'Red' or 'Blue'
  local otherName=event.actor==1 and 'Blue' or 'Red'
  local attackerHp=event.attackerHpStart+(bonusDone and event.heal.actual or 0)
  local defenderHp=impact and event.defenderHpEnd or event.defenderHpStart
  local gold={1,.83,.46}
  local amber={1,.64,.28}
  local red={1,.41,.36}
  local ice={.66,.88,1}
  battleBackdrop(w,h,event.actor,h*.642)
  local hitTime=resolved and elapsed-IMPACT or 10
  local hitTint=not event.landed and ice or event.attackerClass=='wizard' and {.83,.54,1}
    or event.attackerClass=='ogre' and {.93,.55,.29} or amber

  local label,detail,tint='ATTACK ROLL','Roll higher than Shield '..event.shield,gold
  if result and event.defeated and event.wallHealth then
    label,detail,tint='WALL BREACHED','The hex is open for movement.',amber
  elseif result and event.defeated then
    label=playerAttacks and 'VICTORY' or teamName:upper()..' WINS'
    detail=playerAttacks and 'Your Foe is Defeated' or otherName..' defender defeated.'
  elseif resolved and event.landed then
    label,tint=('%d DAMAGE'):format(event.damage),amber
    detail=('Rolled %d against Shield %d'):format(event.roll,event.shield)
    if event.firstFortHit then detail='Fortress Hit  •  '..detail
    elseif newlyCritical(event) then detail='Critical Health  •  '..detail;tint=red end
  elseif resolved then
    label,tint='ATTACK REPELLED',ice
    detail=('Rolled %d against Shield %d'):format(event.roll,event.shield)
  elseif revealed then
    detail=('Rolled %d against Shield %d'):format(event.roll,event.shield)
  end
  if practice then
    if impact then
      detail=('Roll %d beats Shield %d  ·  %d Health lost'):format(event.roll,event.shield,event.damage)
    elseif not revealed then
      detail=('Archer Power %d  ·  Target Shield %d'):format(attacker.power,event.shield)
    end
  end
  local damageHeadline=impact and not (result and event.defeated)
  local headlineFont=damageHeadline and fonts.finale or fonts.large
  if ready then
    local entrance=smoothstep(view.elapsed/.25)
    local alpha=math.min(entrance,smoothstep(-elapsed/.14))
    local y=h*.057+9*(1-entrance)
    local headline=view.quick and 'Attack Roll' or 'Ready for Combat'
    combatTitle(headline,w*.5,y,w-28,gold,1.10+.22*(1-entrance),fonts.large,alpha)
  else
    local alpha=1
    if event.defeated and resolved then
      alpha=result and smoothstep(resultAge/.24) or smoothstep(-resultAge/.18)
    end
    combatTitle(label,w*.5,h*.057,w-28,tint,hitTime<.20 and 1.12 or 1,
      headlineFont,alpha,damageHeadline)
  end
  local detailAlpha=1-transfer
  if event.defeated then
    if result then detailAlpha=smoothstep(resultAge/.24)
    elseif resolved then detailAlpha=smoothstep(-resultAge/.18) end
  end
  if detailAlpha>0 then
    local titleScale=ready and 1.32 or hitTime<.20 and 1.12 or 1
    local detailY=math.max(h*.135,h*.057+fontHeight(headlineFont)*titleScale+4)
    combatTitle(detail,w*.5,detailY,w-24,palette.text,1,practice and fonts.guide or fonts.small,detailAlpha)
  end

  local cy=h*.557
  local fighterH=h*(h<365 and .275 or .30)
  local fighterW=w*.39
  local x1,x2=w*.23,w*.77
  local dieSize=math.min(w*.087,h*.067,48)
  -- The square Archer art sets the highest possible portrait edge at this size.
  -- Keep a steady anchor across matchups, lifting it farther on shorter viewports.
  local portraitTop=cy-math.min(fighterW,fighterH)
  local diceY=math.min(h*.310,portraitTop-dieSize*.42)
  local nameY=math.min(h*.245,portraitTop-fontHeight(fonts.stat)-math.max(4,h*.012))
  local bh=math.max(32,math.min(48,h*.085))
  local boxX,boxY,boxW=w*.12,h*.670,w*.76
  local fullBoxH=h-bh-math.max(18,math.min(32,h*.052))-boxY-9
  local buttonY=(boxY+fullBoxH+(h-4)-bh)*.5
  local statBoxH=math.min(fullBoxH,math.max(h*.080,fontHeight(fonts.stat)*2.5))
  local boxH=statBoxH+(fullBoxH-statBoxH)*transfer
  local middle=boxY+boxH*.5
  local footerDieSize=math.min(w*.070,fullBoxH*.33,46)
  if transfer<1 then
    g.setColor(.035,.035,.05,.82*(1-transfer))
    g.circle('fill',w*.5,diceY,dieSize*1.16)
    color(palette.gold,.37*(1-transfer));g.setLineWidth(1.15)
    g.circle('line',w*.5,diceY,dieSize*1.16)
  end
  if transfer==0 then
    drawD12(g,w*.5,diceY,revealed and event.roll or 12,
      not ready and not revealed and elapsed or nil,event.actor,dieSize,fonts.stat,ready and 'D12' or nil)
  end
  local strike=event.landed and strikePulse(elapsed,1.67,2,2.44) or 0
  local recoil=resolved and strikePulse(elapsed,1.99,2.11,2.49)
    *(event.attackerClass=='ogre' and 1.35 or event.landed and 1 or .55) or 0
  combatTitle(teamName..' '..attacker.name,x1,nameY,w*.40,teamLabels[event.actor],1,fonts.stat)
  combatTitle(event.wallHealth and defender.name or otherName..' '..defender.name,
    x2,nameY,w*.40,event.wallHealth and palette.gold or teamLabels[3-event.actor],1,fonts.stat)
  for _,cx in ipairs({x1,x2}) do
    g.setColor(.025,.025,.032,.72)
    g.polygon('fill',cx-w*.13,cy,cx-w*.07,cy-h*.015,cx+w*.10,cy-h*.013,cx+w*.14,cy+h*.005,
      cx+w*.07,cy+h*.012,cx-w*.08,cy+h*.011)
  end
  if hitTime<.24 then
    color(hitTint,(event.firstFortHit and .26 or .14)*(1-hitTime/.24))
    g.circle('fill',x2,cy-fighterH*.45,fighterH*.48)
  end
  if event.defeated and impact then
    drawFallenFighter(event.defenderClass,3-event.actor,x2,cy,w*.39,fighterH,-1,defenderHp,hitTime,event.wallHealth)
  else
    drawFighter(event.defenderClass,3-event.actor,x2,cy,w*.39,fighterH,-1,0,recoil,defenderHp,nil,event.wallHealth)
  end
  local launchX,launchY,arrowLength=drawFighter(event.attackerClass,event.actor,x1,cy,w*.39,fighterH,
    1,strike,0,attackerHp,nil,nil,elapsed>=1.66)
  if attacker.projectile then
    drawBattleShot(event.attackerClass,launchX,x2,launchY,math.max(5,h*.025),elapsed,cy-fighterH*.47,arrowLength)
  end
  local barY=h*.579
  if event.defeated and impact then
    if event.wallHealth then
      timers.variantUI.explosion(g,x2,cy-fighterH*.36,fighterH*.25,hitTime)
    else
      local skullY=(nameY+fontHeight(fonts.stat)+barY)*.5
      drawDefeatSkull(x2,skullY,math.min(w*.101,h*.089),hitTime)
    end
  end
  local defenderFill=event.defenderHpStart+(defenderHp-event.defenderHpStart)*smoothstep(hitTime/.30)
  local attackerFill=attackerHp
  if bonusDone then
    attackerFill=event.attackerHpStart+event.heal.actual*smoothstep((bonus-BONUS_TIME)/.32)
  end
  battleBar(x1,barY,w*.34,attackerFill,attacker.hp)
  battleBar(x2,barY,w*.34,defenderFill,defender.hp)
  text(('%d / %d HEALTH'):format(attackerHp,attacker.hp),x1-w*.20,barY+11,w*.40,'center',fonts.cardHint)
  text(('%d / %d HEALTH'):format(defenderHp,defender.hp),x2-w*.20,barY+11,w*.40,'center',fonts.cardHint)
  if hitTime<.72 then
    local travel=hitTime/.72
    local kind=event.attackerClass
    local radius=(kind=='ogre' or kind=='fortress') and 45 or 29
    local px,py=x2,cy-fighterH*.47
    for i=1,kind=='wizard' and 12 or 8 do
      local angle=i*2.39996
      local reach=8+travel*radius*(1+i%3*.27)
      local dx,dy=math.cos(angle),math.sin(angle)
      local x,y=px+dx*reach,py+dy*reach
      color(hitTint,(1-travel)*.84)
      g.setLineWidth(kind=='ogre' and 3 or 1.7)
      if kind=='wizard' then
        g.line(x,y,x+dx*5-dy*4,y+dy*5+dx*4,x+dx*13,y+dy*13)
      else
        g.line(x,y,x+dx*8,y+dy*8)
      end
    end
    if kind=='ogre' or event.firstFortHit or not event.landed then
      color(hitTint,(1-travel)*.66);g.setLineWidth(2)
      g.circle('line',px,py,10+travel*radius)
    end
    combatTitle(impact and '-'..event.damage or 'BLOCKED',x2,cy-fighterH*.53-travel*25,
      w*.39,impact and red or ice,1.35-travel*.35,fonts.large,1-travel*.55)
  end

  local mint={.71,1,.84}
  g.setColor(.059-.006*rewardMix,.078+.042*rewardMix,.105-.005*rewardMix,.86+.06*rewardMix)
  g.rectangle('fill',boxX,boxY,boxW,boxH,9,9)
  frame(boxX,boxY,boxW,boxH,.75,9)
  local dieX=boxX+boxW*.165
  local divider=boxX+boxW*.33
  local messageX=divider+boxW*.335

  local function centered(label,x,y,width,font,tint,bold,alpha)
    if alpha<=0 then return end
    local scale=math.min(1,boxH*.27/fontHeight(font))
    combatTitle(label,x,y-fontHeight(font)*scale*.5,width,tint,scale,font,alpha,bold)
  end
  local function statLine(label,x,alpha,tint)
    centered(label,x,middle,boxW*.46,fonts.stat,tint,false,alpha)
  end
  local function resultLine(label,tint,note,alpha)
    if alpha<=0 then return end
    color(palette.gold,.27*alpha);g.setLineWidth(1)
    g.line(divider,boxY+boxH*.21,divider,boxY+boxH*.79)
    local rowOffset=note and boxH*.16 or 0
    centered(label,messageX,middle-rowOffset,boxW*.63,fonts.medium,tint,true,alpha)
    if note then
      centered(note,messageX,middle+rowOffset,boxW*.63,fonts.small,palette.text,false,alpha)
    end
  end

  local summaryAlpha=1-smoothstep(rewardMix*2)
  if transfer>0 and summaryAlpha>.10 then
    drawD12(g,w*.5+(dieX-w*.5)*transfer,diceY+(middle-diceY)*transfer,event.roll,nil,event.actor,
      (dieSize+(footerDieSize-dieSize)*transfer)*summaryAlpha,fonts.stat)
  end
  statLine(('Power %d'):format(attacker.power),boxX+boxW*.25,1-transfer,palette.text)
  statLine(('Shield %d'):format(event.shield),boxX+boxW*.75,1-transfer,palette.gold)

  if result and summaryAlpha>0 then
    local message=event.defeated and ('%d DAMAGE'):format(event.damage)
      or ('Roll %d  /  Shield %d'):format(event.roll,event.shield)
    local note
    if not event.defeated then
      if practice and impact then note=('%d Health lost'):format(event.damage)
      elseif event.firstFortHit then note='Fortress Hit'
      elseif newlyCritical(event) then note='Critical Health' end
    end
    resultLine(message,event.defeated and amber or tint,note,
      smoothstep((resultAge-.13)/.28)*summaryAlpha)
  end

  local rewardAlpha=smoothstep((rewardMix-.5)*2)
  if rewardAlpha>0 and event.fullHealth then
    local x=w*.5
    centered('AMAZING',x,middle-boxH*.26,boxW*.90,fonts.large,mint,true,rewardAlpha)
    centered('No reward roll needed',x,middle,boxW*.92,fonts.small,palette.text,true,rewardAlpha)
    centered('Already at full Health',x,middle+boxH*.23,boxW*.92,fonts.small,palette.text,false,rewardAlpha)
  elseif rewardAlpha>0 and event.heal then
    local shift=bonus and smoothstep((bonus-BONUS_LEAD+.23)/.23) or 0
    local promptAlpha=rewardAlpha*(1-shift)
    centered('VICTORY REWARD',w*.5,middle-boxH*.17,boxW*.92,fonts.medium,mint,true,promptAlpha)
    local prompt=bonus and 'Rolling for Health' or playerAttacks and 'Roll to recover Health'
      or teamName..' earned a Health roll'
    centered(prompt,w*.5,middle+boxH*.17,boxW*.92,fonts.small,palette.text,false,promptAlpha)
    if bonus and bonus>=BONUS_LEAD then
      local entrance=smoothstep((bonus-BONUS_LEAD)/.24)
      local spin=not bonusDone and bonus-BONUS_LEAD or nil
      if entrance>.10 then
        drawD12(g,dieX,middle,event.heal.roll,spin,event.actor,footerDieSize*entrance,fonts.stat)
      end
      if bonusDone then
        resultLine(('+%d HEALTH'):format(event.heal.actual),mint,nil,smoothstep((bonus-BONUS_TIME)/.28))
      else
        resultLine('Rolling for Health',mint,nil,entrance*smoothstep((BONUS_TIME-bonus)/.16))
      end
    end
  end

  view.button=nil
  local action,actionAlpha
  if event.heal and not bonus and playerAttacks then
    action,actionAlpha='Roll for Reward',smoothstep((resultAge-REWARD_REVEAL-REWARD_FADE)/.22)
  elseif bonusDone then
    action,actionAlpha='CONTINUE',smoothstep((bonus-BONUS_TIME-BONUS_HOLD)/.22)
  elseif event.fullHealth then
    action,actionAlpha='CONTINUE',smoothstep((resultAge-REWARD_REVEAL-REWARD_FADE-.45)/.22)
  elseif not event.heal then
    action,actionAlpha='CONTINUE',smoothstep((resultAge-RESULT_GLIDE)/.22)
  end
  if not practice and mode=='online' and (event.actor~=onlineSide or pending or not onlineAllowed) then
    view.ready=actionAlpha and actionAlpha>=.70 or (event.heal and not bonus and rewardAlpha>=.9)
    if view.ready then
      text(event.actor==onlineSide and 'Synchronizing…' or
        ((zompa.opponentName() or 'Opponent')..(event.heal and not bonus and ' will roll for Health' or ' is continuing…')),
        10,buttonY+(bh-fontHeight(fonts.small))*.5,w-20,'center',fonts.small)
    end
    return
  end
  if actionAlpha and actionAlpha>0 then
    local box={x=w*.16,y=buttonY,w=w*.68,h=bh}
    luxeButton(action,box.x,box.y,box.w,box.h,false,actionAlpha)
    if actionAlpha>=.70 then view.button=box end
  end
end
local function drawDeathMatch(view)
  local g=love.graphics
  local w,h=layout.w,layout.h
  local event=view.event
  local duel=event.deathMatch
  local elapsed=view.elapsed
  local round=math.max(1,math.min(#duel.rounds,1+math.floor((elapsed-DUEL_INTRO)/DUEL_ROUND)))
  local time=elapsed-DUEL_INTRO-(round-1)*DUEL_ROUND
  local rolls=duel.rounds[round]
  local impactTime=time-DUEL_REVEAL
  local deciding=round==#duel.rounds
  local resolved=deciding and impactTime>=0
  local strike=deciding and strikePulse(impactTime,-.25,0,.35) or 0
  local active=time>=0 and time<DUEL_LAND and 1
    or time>=DUEL_SECOND and time<DUEL_SECOND+DUEL_LAND and 2 or nil
  local ember={1,.37,.31}
  local ivory={1,.88,.71}
  local gold={1,.80,.42}
  local owners={event.actor,3-event.actor}
  local classes={event.attackerClass,event.defenderClass}
  local hp={event.attackerHpStart,event.defenderHpStart}
  local winningTeam=teamNames[owners[duel.winner]]
  local motion=math.max(0,1-elapsed/.60)*7
  if resolved then motion=math.max(0,1-impactTime/.47)*10 end
  local shaking=motion>0 and g.push and g.translate
  if shaking then
    g.setColor(.07,.023,.044,1);g.rectangle('fill',0,0,w,h)
    g.push()
    g.translate(motion*math.sin(elapsed*84),motion*.59*math.cos(elapsed*103))
  end
  battleBackdrop(w,h,event.actor)
  g.setColor(.12,.018,.046,.55);g.rectangle('fill',5,5,w-10,h-10,9,9)
  color(ember,.53);g.setLineWidth(1.4);g.rectangle('line',4,4,w-8,h-8,10,10)
  local entrance=smoothstep(elapsed/.32)
  local titleY=h*.150-(1-entrance)*h*.026
  g.setColor(.23,.035,.064,.86*entrance)
  g.polygon('fill',w*.12,h*.139,w*.94,h*.139,w*.88,h*.252,w*.06,h*.252)
  g.setColor(.73,.21,.21,.5*entrance);g.setLineWidth(1)
  g.line(w*.12,h*.139,w*.94,h*.139)
  g.line(w*.06,h*.252,w*.88,h*.252)
  for i=1,25 do
    local a=i*2.39996
    local x=w*.5+math.cos(a)*w*(.20+i%7*.036)
    local y=h*.166+math.sin(a)*h*(.012+i%5*.012)
    g.setColor(.64,.034,.078,entrance*(.20+i%4*.10))
    g.circle('fill',x,y,1+i%5*.63)
  end
  local skullY=h*.093
  local skullSize=math.min(h*.042,w*.045,25)
  color(gold,.38*entrance);g.setLineWidth(1)
  g.line(w*.16,skullY,w*.5-skullSize*1.5,skullY)
  g.line(w*.5+skullSize*1.5,skullY,w*.84,skullY)
  duelSkull(g,w*.5,skullY,skullSize,entrance,animationTime)
  combatTitle('DEATH MATCH',w*.5,titleY,w*.88,ivory,
    math.min(1+.46*(1-entrance),h*.105/fontHeight(fonts.finale)),fonts.finale,entrance,true)

  local headline='BOTH COMBATANTS ARE CRITICAL'
  local detail='Higher roll wins. One combatant falls.'
  local tint=ivory
  if resolved then
    headline=winningTeam:upper()..' WINS'
    detail=teamNames[owners[3-duel.winner]]..' '..rules.classes[classes[3-duel.winner]].name..' is defeated.'
    tint=gold
  elseif active then
    headline=teamNames[owners[active]]:upper()..' ROLLS'
    detail='Round '..round..'  •  Highest D12 wins'
    tint=teamLabels[owners[active]]
  elseif time>=DUEL_REVEAL then
    headline='TIED  •  ROLL AGAIN'
    detail='Both combatants roll again.'
    tint=gold
  elseif time>=DUEL_SECOND+DUEL_LAND then
    headline='THE DICE HAVE LANDED'
  elseif time>=DUEL_LAND then
    headline=teamNames[owners[1]]:upper()..' ROLLS '..rolls[1]
    detail=teamNames[owners[2]]..' rolls next.'
  end
  local headerY=h*.275
  local resultScale=resolved and 1.10+.28*(1-smoothstep(impactTime/.32)) or 1
  combatTitle(headline,w*.5,headerY,w*.90,tint,
    math.min(resultScale,h*.065/fontHeight(fonts.large)),fonts.large,1,true)
  combatTitle(detail,w*.5,h*.343,w*.90,palette.text,
    math.min(1,h*.049/fontHeight(fonts.small)),fonts.small)
  local shotPhase=IMPACT+impactTime
  local shotX,shotY,shotArrow
  for side=1,2 do
    local cx=w*(side==1 and .27 or .73)
    local baseY=h*.603
    local fighterH=h*.210
    local teamTint=teamLabels[owners[side]]
    local losing=resolved and side~=duel.winner
    local focus=side==active or resolved and not losing
    local fall=losing and smoothstep((impactTime-.09)/.74) or 0
    local direction=side==1 and 1 or -1
    local glow=focus and teamTint or ember
    for ring=4,1,-1 do
      color(glow,(focus and .11 or .044)*(1-fall))
      g.circle('fill',cx,baseY-fighterH*.48,math.min(w*.16,h*.102)*(1+ring*.13))
    end
    if losing then
      drawFallenFighter(classes[side],owners[side],cx,baseY,w*.42,fighterH,direction,hp[side],impactTime)
      local size=math.min(w*.109,h*.08)
      drawDefeatSkull(cx,baseY-fighterH*.46-size*.49,size,impactTime)
    else
      local isWinner=side==duel.winner
      local arrowReleased=deciding and isWinner and shotPhase>=1.66
      local x,y,length=drawFighter(classes[side],owners[side],cx,baseY,w*.42,fighterH,direction,
        isWinner and strike or 0,0,hp[side],nil,nil,arrowReleased)
      if isWinner then shotX,shotY,shotArrow=x,y,length end
    end
    local name=teamNames[owners[side]]..' '..rules.classes[classes[side]].name
    combatTitle(name,cx,h*.612,w*.435,teamTint,1,fonts.stat)
    local scoreY=h*.680
    local scoreW=w*.395
    local scoreH=h*.157
    g.setColor(.075,.028,.047,.93);g.rectangle('fill',cx-scoreW*.5,scoreY,scoreW,scoreH,8,8)
    color(focus and (resolved and gold or teamTint) or teamTint,focus and .94 or .34)
    g.setLineWidth(focus and 2 or 1)
    g.rectangle('line',cx-scoreW*.5,scoreY,scoreW,scoreH,8,8)
    local start=side==1 and 0 or DUEL_SECOND
    local shown=time>=start+DUEL_LAND
    if shown or side==active then
      local size=math.min(w*.081,h*.065,53)
      local rowCenter=scoreY+scoreH*.355
      local numberScale=math.min(1,scoreH*.54/fontHeight(fonts.finale))
      drawD12(g,cx-scoreW*.24,rowCenter,rolls[side],
        not shown and time-start or nil,owners[side],size,fonts.stat)
      combatTitle(shown and tostring(rolls[side]) or '···',cx+scoreW*.20,
        rowCenter-fontHeight(fonts.finale)*numberScale*.5,scoreW*.47,losing and ember or ivory,
        numberScale,fonts.finale,1,true)
    end
    local status=resolved and (losing and 'FALLEN' or 'VICTOR')
      or shown and 'ROLL LOCKED' or side==active and 'ROLLING' or 'AWAITING ROLL'
    combatTitle(status,cx,scoreY+scoreH*.72,scoreW,losing and ember or focus and gold or ivory,
      math.min(1,scoreH*.255/fontHeight(fonts.cardHint)),fonts.cardHint)
  end
  if deciding then
    local winner=duel.winner
    local kind=classes[winner]
    if rules.classes[kind].projectile and shotX then
      local target=w*(winner==1 and .73 or .27)
      drawBattleShot(kind,shotX,target,shotY,math.max(5,h*.024),shotPhase,h*.504,shotArrow)
    end
  end
  if resolved and impactTime<.16 then
    color(ember,(.16-impactTime)*1.5);g.rectangle('fill',0,0,w,h)
  end
  if shaking then g.pop() end
  view.button=nil
  if resolved and impactTime>=1.46 then
    local bh=math.max(23,math.min(47,h*.077))
    local scoreBottom=h*(.680+.157)
    local box={x=w*.18,y=(scoreBottom+(h-4)-bh)*.5,w=w*.64,h=bh}
    if mode=='online' and (event.actor~=onlineSide or pending or not onlineAllowed) then
      view.ready=true
      text(event.actor==onlineSide and 'Synchronizing…' or 'Waiting for opponent…',10,box.y+(bh-fontHeight(fonts.small))*.5,w-20,'center',fonts.small)
      return
    end
    luxeButton('CONTINUE',box.x,box.y,box.w,box.h,false)
    view.button=box
  end
end
local OPENING = {beat=1.65,land=.85,resultHold=2.35}
local SIEGE_BEAT, FINALE_LENGTH = 2.35, 6
local function playerName(side)
  if mode=='solo' then return side==1 and 'You' or 'CPU' end
  if mode=='online' and onlineSide then
    if side==onlineSide then return 'You' end
    return zompa.opponentName() or 'Opponent'
  end
  return teamNames[side]
end

local function openingButton(label,x,y,w,h,primary)
  local g=love.graphics
  g.setColor(0,0,0,.35)
  g.rectangle('fill',x,y+3,w,h,7,7)
  if primary then g.setColor(.32,.19,.075,1)
  else g.setColor(.105,.12,.15,1) end
  g.rectangle('fill',x,y,w,h,7,7)
  frame(x,y,w,h,primary and 1 or .63,8)
  combatTitle(label,x+w*.5,y+(h-fontHeight(fonts.small))*.5,w,palette.text,1,fonts.small)
  return {x=x,y=y,w=w,h=h}
end

local function drawIntroduction(scene, opacity)
  local g=love.graphics
  local w,h=layout.w,layout.h
  if not scene then
    local header=layout.topReserve
    if logo then
      local iw,ih=logo:getDimensions()
      local scale=math.min(w*.90/iw,(header-36)/ih)
      g.setColor(1,1,1,1)
      g.draw(logo,(w-iw*scale)*.5,3,0,scale,scale)
    else
      combatTitle('FORTRESS SIEGE',w*.5,3,w-16,palette.gold)
      text('FINAL CONQUEST',8,6+fontHeight(fonts.large),w-16,'center',fonts.small)
    end
    local missionY=header-fontHeight(fonts.cardHint)-11
    text('Lead your army. Destroy the enemy fortress.',8,missionY,w-16,'center',fonts.cardHint)
    for i=1,18 do
      local px=w*((i*.173+introTime*(.014+i%3*.006))%1)
      local py=layout.y+layout.boardH*((i*.293-introTime*.025)%1)
      color(palette.gold,.18+.13*math.sin(i+introTime))
      g.circle('fill',px,py,1+i%3*.45)
    end
    for side=1,2 do
      local fort=state.forts[side]
      local _,fy=center(fort.r,fort.c)
      local name=playerName(side)
      local label=name==teamNames[side] and name or name..' · '..teamNames[side]
      local badgeW=(w-layout.boardW*3/7)*.5-10
      local bx=side==1 and 6 or w-badgeW-6
      combatTitle(label,bx+badgeW*.5,fy-fontHeight(fonts.openingSide)*.5,badgeW+8,teamLabels[side],1,fonts.openingSide)
    end
    local y,bh=layout.actionY,layout.actionH
    if mode~='online' or onlineSide==1 then
      intro.start=openingButton('Start Game',10,y,w*.53-13,bh,true)
    else
      intro.start=nil
      combatTitle(onlineSide and 'Waiting for inviter…' or 'Connecting…',w*.26,y+5,w*.49,palette.text,1,fonts.small)
    end
    intro.guide=openingButton('How to Play',w*.53+4,y,w*.47-14,bh,false)
    return
  end
  if introTime<introDuration then
    local t=introTime
    local drift=smoothstep(t/introDuration)
    local height=layout.viewportH
    local function drawScene(a)
      local function layer(image,x,y,scale,mirror)
        if not image then return end
        local iw,ih=image:getDimensions()
        g.setColor(1,1,1,a)
        g.draw(image,x,y,0,scale*(mirror or 1),scale,iw*.5,ih*.5)
      end
      g.setColor(.055,.047,.071,a)
      g.rectangle('fill',0,0,w,height)
      if valley then
        local iw,ih=valley:getDimensions()
        layer(valley,w*(.52-.02*drift),height*.5,math.max(w/iw,height/ih)*(1.05+.035*drift))
      end
      if siegeKeeps[2] then
        local iw,ih=siegeKeeps[2]:getDimensions()
        layer(siegeKeeps[2],w*.52,height*.49,math.min(w*.71/iw,height*.38/ih)*(1+.035*drift))
      end
      for side=1,2 do
        local dir=side==1 and 1 or -1
        local image=fighterArt[side][side==1 and 'soldier' or 'barbarian']
        if image then
          local iw,ih=image:getDimensions()
          local size=math.min(w*.62/iw,height*.40/ih)
          layer(image,w*(.5-dir*(.40-.065*drift)),height*.745-ih*size*.5,size,dir)
        end
      end
      for i=0,31 do
        local fraction=i/31
        g.setColor(.045,.034,.062,a*smoothstep(fraction)*.96)
        local top=math.floor(height*(.60+.40*i/32))
        g.rectangle('fill',0,top,w,math.floor(height*(.60+.40*(i+1)/32))-top)
      end
      for i=1,15 do
        local px=w*((i*.617+t*.008)%1)
        local py=height*(.68-((i*.113+t*.036)%.36))
        g.setColor(1,.71,.33,a*(.23+.14*math.sin(i+t*2)))
        g.circle('fill',px,py,.7+i%3*.35)
      end
      if logo then
        local iw,ih=logo:getDimensions()
        layer(logo,w*.5,height*(.17+.023*drift),math.min(w*.89/iw,height*.26/ih)*(1+.018*drift))
      end
      local reveal=smoothstep((t-.28)/.60)
      combatTitle('LEAD YOUR ARMY',w*.5,height*.775+(1-reveal)*8,w*.88,palette.gold,1,fonts.large,a*reveal,true)
      reveal=smoothstep((t-.82)/.62)
      combatTitle('Destroy the enemy fortress.',w*.5,height*.845+(1-reveal)*6,w*.9,palette.text,1,fonts.medium,a*reveal)
      g.setColor(.055,.044,.066,1-smoothstep(t/.32))
      g.rectangle('fill',0,0,w,height)
    end
    drawScene(opacity or 1)
  end
end

-- Practice uses a separate board and seed, with units introduced as needed.
local PRACTICE_SOLDIER,PRACTICE_ARCHER,PRACTICE_FOE=12,4,27
local practiceStats={
  {'health','Health','The first number is Health left. The second is full Health. At zero, the piece is defeated.'},
  {'move','Move','How many hexes the piece can move. This Soldier moves one hex toward the enemy.'},
  {'power','Power','How much Health a successful attack removes from the target.'},
  {'range','Range','How far away the target can be. Range 1 means the target must be next to this piece.'},
  {'shield','Shield','The attacker must roll higher than the target’s Shield to land a hit.'},
}
local practiceSteps={
  inspect={1,'Inspect a Piece','Tap the highlighted Red Soldier to open its stat card.'},
  move={2,'Choose a Destination','Gold hexes show where the Soldier can move. Tap either one.'},
  confirmMove={2,'Confirm the Move','Tap Move Here. In a match, one move or attack ends your turn.'},
  moving={2,'Move Confirmed','Your Soldier has moved forward.'},
  archer={3,'Select Your Archer','Tap the highlighted Red Archer. It can shoot over troops up to 3 hexes away.'},
  target={3,'Choose a Target','Archers shoot in a straight line. Tap the Blue Soldier with the icy-blue rim.'},
  confirmAttack={3,'Confirm the Attack','Archer Power 6. Target Shield 2. Tap Attack Now. The die rolls automatically.'},
  objective={4,'Your Objective','Tap the marked Blue Fortress. Destroying it wins a match.'},
  expand={4,'Read the Fortress Card','Tap the down arrow on the card. Check its status and learn when it can fire.'},
  complete={4,'Ready for the Siege','Protect your fortress and attack the enemy’s. Each turn, choose one move or attack.'},
}

local function startPractice()
  local board=rules.new(1,1)
  for _,unit in ipairs(board.units) do unit.hp=0 end
  board.units[PRACTICE_SOLDIER].hp=rules.classes.soldier.hp
  local archer=board.units[PRACTICE_ARCHER]
  archer.r,archer.c=6,4
  local foe=board.units[PRACTICE_FOE]
  foe.r,foe.c=4,3
  return {board=board,step='inspect'}
end

local function practiceMarker(cell,attack,chosen,selectedAt)
  local cx,cy=center(cell.r,cell.c)
  if attack then targetMarker(cx,cy,layout.radius,chosen,selectedAt)
  else moveMarker(cx,cy,layout.radius) end
end

local function practiceCallout(unit,label)
  local g=love.graphics
  local cx,cy=center(unit.r,unit.c)
  local radius=layout.radius*1.18
  local side=cx<layout.w*.5 and 1 or -1
  local labelW=math.min(122,layout.w*.39)
  local labelH=fontHeight(fonts.guide)+8
  local x=side==1 and cx+radius+10 or cx-radius-10-labelW
  x=math.max(5,math.min(layout.w-labelW-5,x))
  local y=cy-labelH*.5
  color(palette.gold,.86)
  g.setLineWidth(1.7)
  g.polygon('line',faceHex(cx,cy,radius))
  g.line(cx+side*radius,cy,side==1 and x or x+labelW,cy)
  g.setColor(.06,.072,.104,1)
  g.rectangle('fill',x,y,labelW,labelH,5,5)
  color(palette.gold,.86)
  g.rectangle('line',x,y,labelW,labelH,5,5)
  combatTitle(label,x+labelW*.5,y+4,labelW,palette.text,1,fonts.guide)
end

local function practicePanel(chapter,title,detail,y,h)
  local g=love.graphics
  local w=layout.w
  g.setColor(.063,.078,.105,1)
  g.rectangle('fill',9,y,w-18,h,9,9)
  color(palette.gold,.70);g.setLineWidth(1.2)
  g.rectangle('line',9,y,w-18,h,9,9)
  color(palette.gold)
  g.setFont(fonts.guide)
  local outline={'INSPECT','MOVE','ATTACK','OBJECTIVE'}
  g.printf(('%d / 4   %s'):format(chapter,outline[chapter]),18,y+8,w-36,'left')
  local barW=math.min(16,w*.045)
  for i=1,4 do
    color(palette.gold,i<=chapter and .96 or .26)
    g.rectangle('fill',w-18-(5-i)*(barW+4),y+11,barW,4,2,2)
  end
  combatTitle(title,w*.5,y+25,w-34,palette.gold,1,fonts.medium)
  text(detail,18,y+29+fontHeight(fonts.medium),w-36,'center',fonts.guide)
end

local function drawPractice(practice)
  local g=love.graphics
  local w,h=layout.w,layout.h
  local step,board=practice.step,practice.board
  intro.close,practice.button=nil,nil
  if practice.battle then
    drawBattleOverlay(practice.battle,true)
    intro.close=openingButton('Exit Tutorial',10,h,math.min(100,w*.40),21,false)
    return
  end

  local label
  if step=='expand' then
    drawCard(board.forts[2],'expand')
    if practice.expanded then
      detail.piece=board.forts[2]
      detail.draw(layout,siegeKeeps[2],rules.classes.fortress,rules.attackRange('fortress'),animationTime-practice.openedAt)
      return
    end
    local lesson=practiceSteps.expand
    practicePanel(4,lesson[2],lesson[3],layout.topReserve+2,104)
  elseif step=='stats' then
    local stat=practiceStats[practice.stat]
    g.setColor(.035,.025,.058,.67)
    g.rectangle('fill',0,0,w,h)
    drawCard(board.units[PRACTICE_SOLDIER],stat[1])
    local panelY=layout.topReserve+2
    local panelH=math.min(104,layout.actionY-panelY-5)
    practicePanel(1,('%s  ·  %d / %d'):format(stat[2],practice.stat,#practiceStats),stat[3],panelY,panelH)
    label=practice.stat==#practiceStats and 'Practice Moving' or 'Next Stat'
  else
    local lesson=practiceSteps[step]
    practicePanel(lesson[1],lesson[2],lesson[3],5,layout.topReserve-8)
    if step=='inspect' then
      practiceCallout(board.units[PRACTICE_SOLDIER],'Red Soldier')
    elseif step=='move' then
      for key in pairs(rules.moves(board,PRACTICE_SOLDIER)) do
        local r,c=rules.fromkey(key)
        practiceMarker({r=r,c=c})
      end
    elseif step=='confirmMove' then
      practiceMarker(practice.destination,false,true)
      label='Move Here'
    elseif step=='archer' then
      practiceCallout(board.units[PRACTICE_ARCHER],'Red Archer')
    elseif step=='target' or step=='confirmAttack' then
      practiceMarker(board.units[PRACTICE_FOE],true,step=='confirmAttack',practice.selectedAt)
      if step=='confirmAttack' then label='Attack Now' end
    elseif step=='objective' then
      practiceCallout(board.forts[2],'Blue Fortress')
    elseif step=='complete' then
      label=mode=='online' and onlineSide~=1 and 'Finish Tutorial' or 'Start Game'
    end
  end
  local y,bh=layout.actionY,layout.actionH
  intro.close=openingButton('Exit Tutorial',10,y,w*.38-9,bh,false)
  if label then
    practice.button=openingButton(label,w*.38+7,y,w*.62-17,bh,true)
  end
end

local function drawOpening(view)
  local g=love.graphics
  local w,h=layout.w,layout.h
  local opening=view.opening
  local rolls,rolling,winner,phase
  if view.elapsed then
    local count=#opening.rounds
    local index=math.min(count,math.floor(view.elapsed/OPENING.beat)+1)
    phase=view.elapsed-(index-1)*OPENING.beat
    rolls=opening.rounds[index]
    rolling=phase<OPENING.land and phase or nil
    if not rolling and rolls[1]~=rolls[2] then winner=opening.first end
  end

  local pw,ph=math.min(w-20,430),math.min(283,h-12,math.max(168,h*.73))
  local x,y=(w-pw)*.5,timers.variantUI.boardDialogTop(layout,ph)
  g.setColor(.018,.016,.027,.43);g.rectangle('fill',0,0,w,layout.viewportH)
  g.setColor(.01,.009,.016,.48);g.rectangle('fill',x,y+5,pw,ph,13,13)
  g.setColor(.064,.070,.096,.99);g.rectangle('fill',x,y,pw,ph,12,12)
  frame(x+.5,y+.5,pw-1,ph-1,.85,12)
  local headerH=ph*.218
  combatTitle('Roll to See Who Goes First',w*.5,y+(headerH-fontHeight(fonts.medium))*.5,
    pw-18,palette.gold,1,fonts.medium,1,true)
  local interiorY,interiorH=y+headerH,ph*.527
  local margin,gap=13,10
  local cellW=(pw-2*margin-gap)*.5
  local size=math.min(cellW*.27,interiorH*.34,46)
  for side=1,2 do
    local sx=x+margin+(side-1)*(cellW+gap)
    local cx=sx+cellW*.5
    local red=side==1
    g.setColor(red and .128 or .076,red and .075 or .109,red and .087 or .170,1)
    g.rectangle('fill',sx,interiorY,cellW,interiorH,8,8)
    color(winner==side and palette.gold or teamLabels[side],winner==side and .87 or .31)
    g.setLineWidth(winner==side and 1.45 or 1)
    g.rectangle('line',sx+.5,interiorY+.5,cellW-1,interiorH-1,8,8)
    local diceY=interiorY+interiorH*.415
    drawD12(g,cx,diceY,rolls and rolls[side] or 12,rolling,side,size,fonts.cardHint,not rolls and 'D12' or nil)
    local name=playerName(side)
    local label=name==teamNames[side] and name or name..' · '..teamNames[side]
    combatTitle(label,cx,interiorY+interiorH*.82-fontHeight(fonts.small)*.4,cellW-10,
      teamLabels[side],1,fonts.small)
  end

  view.button,view.backButton=nil,nil
  local bw,bh=cellW,math.min(42,ph*.178)
  local by=y+ph*.792
  local ready=not view.elapsed
  local mayRoll=mode~='online' or onlineSide==1 and onlineAllowed and not pending and lastOnlineCount==0
  if ready and mayRoll then
    view.backButton=openingButton('Back',x+margin,by,bw,bh,false)
    view.button=openingButton('Roll Dice',x+margin+bw+gap,by,bw,bh,true)
    if turnSendFailed then text('Could not send. Tap again to retry.',x+4,y+ph+4,pw-8,'center',fonts.cardHint) end
    return
  end
  local status='Connecting…'
  if rolling then status='Rolling dice…'
  elseif winner then
    local name=playerName(winner)
    status=name=='You' and 'You Go First' or name..' Goes First'
    local pulse=.5+.5*math.cos((phase-OPENING.land)*2*math.pi/1.12)
    local white=.89+.11*pulse
    combatTitle(status,w*.5,by+(bh-fontHeight(fonts.medium))*.5,pw-24,
      {white,white,white},1,fonts.medium,1,true)
    return
  elseif rolls then status='Tie · Rolling again'
  elseif pending or lastOnlineCount==1 then status='Starting roll…'
  elseif onlineSide==2 then status='Waiting for '..playerName(1)..' to roll…' end
  combatTitle(status,w*.5,by+(bh-fontHeight(fonts.small))*.5,pw-24,
    palette.text,1,fonts.small)
end

local function siegeGeometry()
  local w,h=layout.w,layout.h
  return {w*.212,w*.788},h*.574,math.min(w*.36,h*.30,186)
end

local function drawValley(elapsed)
  local g=love.graphics
  local w,h=layout.w,layout.h
  g.setColor(.046,.058,.087,1)
  g.rectangle('fill',0,0,w,layout.viewportH)
  if valley then
    local iw,ih=valley:getDimensions()
    g.setColor(1,1,1,1)
    g.draw(valley,4,4,0,(w-8)/iw,(h-8)/ih)
  end
  -- Feather the text and dice scrims into the sky and the rock below.
  local bands=48
  for i=0,bands-1 do
    local t=i/(bands-1)
    local skyStart=5+math.floor(i*h*.32/bands)
    local skyEnd=5+math.floor((i+1)*h*.32/bands)
    g.setColor(.023,.030,.05,.58*(1-smoothstep(t)))
    g.rectangle('fill',5,skyStart,w-10,skyEnd-skyStart)
    local groundStart=math.floor(h*.55+i*(h*.45-5)/bands)
    local groundEnd=math.floor(h*.55+(i+1)*(h*.45-5)/bands)
    g.setColor(.027,.036,.052,.79*smoothstep(t*1.58))
    g.rectangle('fill',5,groundStart,w-10,groundEnd-groundStart)
  end
  frame(4,4,w-8,h-8,.95)
  for i=1,6 do
    local x=w*(.39+(i*.083+elapsed*.021)%.23)
    local y=h*(.54+i*.010)
    g.setColor(.57,.61,.66,.064)
    g.circle('fill',x,y,w*(.04+i%3*.016))
  end
end

local function shatterKeep(side,x,base,size,age)
  if age>1.64 then return end
  local g=love.graphics
  local alpha=1-smoothstep((age-.47)/1.17)
  local spread=math.min(1,age/.49)
  local pieces=siegeChunks[side]
  for i=1,16 do
    local row,col=math.floor((i-1)/4),(i-1)%4
    local dx=(col-1.5)*.25
    local dy=(row-3.5)*.222
    local direction=dx<0 and -1 or 1
    local px=x+size*(dx+direction*age*(.37+i%7*.11))
    local py=base+size*(dy-age*(.22+i%5*.10)+age*age*.83)
    if pieces then
      g.setColor(1,.86,.69,alpha)
      g.draw(siegeKeeps[side],pieces[i],px,py,direction*age*(1.1+i%5*.42),
        size/240,size/240,30,26)
    else
      local r=size*(.05+i%3*.015)*(1-.48*spread)
      g.setColor(.59,.40,.28,alpha)
      g.polygon('fill',px-r,py,px,py-r,px+r,py-r*.3,px+r*.51,py+r)
    end
  end
  if age<.28 then
    local flash=1-age/.28
    g.setColor(1,.64,.28,flash*.55)
    g.circle('fill',x,base-size*.36,size*(.17+.58*(1-flash)))
    g.setColor(1,.91,.60,flash*.82)
    g.circle('fill',x,base-size*.36,size*(.075+.16*(1-flash)))
    g.setColor(1,.64,.30,flash*.26)
    g.rectangle('fill',5,5,layout.w-10,layout.h-10)
  end
end

local function keepImpact(x,y,size,elapsed,collapse)
  local g=love.graphics
  local duration=collapse and 1.54 or .60
  local p=elapsed/duration
  if p<0 or p>=1 then return end
  local fade=1-p
  for i=1,collapse and 42 or 12 do
    local angle=i*2.39996
    local reach=size*(.075+(i%6)*.043+p*(.23+(i%5)*.11))*(collapse and 1.55 or 1)
    local xx,yy=x+math.cos(angle)*reach,y+math.sin(angle)*reach*.83+p*p*size*.39
    local rock=size*(.022+(i%4)*.008)*fade
    g.setColor(1,.52+i%3*.12,.22,fade*.83)
    g.polygon('fill',xx-rock,yy,xx,yy-rock*1.8,xx+rock,yy,xx,yy+rock*.56)
    if i%2==0 then
      g.setColor(.29,.24,.22,fade*.72)
      g.circle('fill',xx,yy-size*p*.16,size*(.054+p*.13))
    end
  end
  if p<.21 then
    g.setColor(1,.74,.39,(.21-p)*2.7)
    g.circle('fill',x,y,size*(.10+1.5*p))
  end
end

local function drawFinalSiege()
  local g=love.graphics
  local w,h=layout.w,layout.h
  local siege=overlay.siege
  local elapsed=overlay.elapsed
  local index=math.min(#siege.volleys,math.floor(elapsed/SIEGE_BEAT)+1)
  local phase=elapsed-(index-1)*SIEGE_BEAT
  local volley=siege.volleys[index]
  local prior=index>1 and siege.volleys[index-1].hp or siege.start
  local impact=volley.hit>0 and phase>=2
  local hp=impact and volley.hp or prior
  local x,base,size=siegeGeometry()
  local shotY=base-size*.36
  drawValley(elapsed)
  combatTitle('FINAL SIEGE',w*.5,h*.074,w*.86,palette.gold,1,fonts.finale,1,true)
  local caption='VOLLEY '..index
  if siege.deathMatch then
    local ember={1,.49,.38}
    local titleScale=math.min(1.23,h*.052/fontHeight(fonts.medium))
    combatTitle('DEATH MATCH',w*.5,h*.15,w*.84,ember,titleScale,fonts.medium,1,true)
    caption='HIGH ROLL WINS'
    if phase>=1.25 then
      caption=volley.hit==0 and 'TIE  •  REROLL' or (teamNames[volley.hit]:upper()..' WINS')
    end
    local tint=phase>=1.25 and volley.hit>0 and teamLabels[volley.hit] or palette.gold
    combatTitle(caption,w*.5,h*.207,w*.86,tint,1,fonts.stat,1,true)
  else
    if phase>=1.25 then
      caption=volley.hit==0 and 'TIE  •  NO DAMAGE'
        or (volley.hit==1 and 'RED FIRES' or 'BLUE FIRES')
    end
    text(caption,12,h*.18,w-24,'center',fonts.medium)
  end
  local target=volley.hit>0 and 3-volley.hit
  local muzzleX,muzzleY
  for side=1,2 do
    local recoil=impact and side==target and (1-smoothstep((phase-2)/.30)) or 0
    local shake=recoil*math.sin((phase-2)*81)*size*.065
    local direction=side==volley.hit and (side==1 and 1 or -1) or nil
    local launchX,launchY=drawCliffKeep(side,x[side]+shake,base,size,shake/size*.36,1,direction)
    if launchX then muzzleX,muzzleY=launchX,launchY end
  end
  if target then
    drawBattleShot('fortress',muzzleX,x[target],muzzleY,size*.117,phase,shotY)
    if impact then
      keepImpact(x[target],shotY,size,phase-2,siege.deathMatch)
      if siege.deathMatch then
        color({1,.60,.34},.20*strikePulse(phase,1.99,2,2.18))
        g.rectangle('fill',0,0,w,h)
      end
      combatTitle('-'..(prior[target]-hp[target]),x[target],shotY-size*.45-(phase-2)*size*.28,
        w*.34,{1,.58,.39},1.20,fonts.large,1,true)
    end
  end
  for side=1,2 do
    local barY=h*.648
    battleBar(x[side],barY,w*.32,hp[side],rules.FORT_HP)
    text(('%s  %d / %d'):format(teamNames[side]:upper(),hp[side],rules.FORT_HP),
      x[side]-w*.19,barY+12,w*.38,'center',fonts.stat)
    local rolling=phase<1.08 and phase or nil
    local dieSize=math.min(size*.29,h*.086,46)
    if siege.deathMatch and side==volley.hit and phase>=1.25 then
      local glow=1-smoothstep((phase-1.25)/.42)
      color(palette.gold,.14+.21*glow)
      g.circle('fill',x[side],h*.835,dieSize*(.98+.12*glow))
    end
    drawD12(g,x[side],h*.835,side==1 and volley.a or volley.b,rolling,side,dieSize,fonts.stat)
  end
end

function timers.localDefeat(owner)
  return mode=='solo' and owner==2 or mode=='online' and onlineSide~=nil and owner~=onlineSide
end

local function drawFinished()
  local g=love.graphics
  local w,h=layout.w,layout.h
  local owner=state.winner
  if owner==0 then
    g.setColor(0,0,0,.82);g.rectangle('fill',0,0,w,layout.viewportH)
    local top=timers.variantUI.boardDialogTop(layout,h*.40)
    panel(w*.04,top,w*.92,h*.40)
    combatTitle('STALEMATE',w*.5,top+h*.11,w*.85,palette.gold)
    text('Neither kingdom has a legal action.',12,top+h*.24,w-24,'center',fonts.small)
    text('Use the Zompa Back button to leave.',12,top+h*.30,w-24,'center',fonts.small)
    return
  end
  local t=finishElapsed
  local defeated=3-owner
  local x,base,size=siegeGeometry()
  local dueling=state.finish=='siege'
  local age=t-COLLAPSE_TIME
  local lost=timers.localDefeat(owner)
  local tremble=smoothstep(t/.21)*size*.018
  local strain=math.sin(t*72)*tremble
  local angle=math.sin(t*63)*tremble/size*.45
  local shakeScene=age>=0 and age<.60 and g.push and g.translate
  if shakeScene then
    local strength=math.min(12,w*.028)*(1-age/.60)^2
    g.push()
    g.translate(0,math.sin(age*83)*strength*.71)
  end
  drawValley(t)
  drawCliffKeep(owner,x[owner],base,size,0,1)
  if age<0 then
    drawCliffKeep(defeated,x[defeated],base+strain,size,angle,1)
  else
    shatterKeep(defeated,x[defeated],base,size,age)
    keepImpact(x[defeated],base-size*.32,size,age,true)
    timers.finaleArt.debris(g,x[defeated],base,size,age)
    local skullSize=size*(lost and .31 or .26)
    local skullOpacity=lost and (1-smoothstep((age-1.08)/.68)) or 1
    drawDefeatSkull(x[defeated],base-size*(.44+.31*.49),skullSize,age-.26,skullOpacity)
  end
  if t<1.40 then
    combatTitle(dueling and 'FINAL SIEGE' or 'THE FINAL BLOW',w*.5,h*.09,w*.88,
      palette.gold,1,fonts.finale,1-smoothstep((t-1.19)/.21),true)
  else
    local party=t-1.40
    local winnerTint=teamLabels[owner]
    local reveal=smoothstep(party/.40)
    local zoom=1-(1-math.min(1,party/.62))^3
    local flare=lost and 0 or math.sin(math.pi*math.min(1,party/.68))
    local rest=lost and .96 or 1
    local titleY=h*(.124+(lost and -.014 or .022)*(1-zoom))
    local trim=lost and {.73,.65,.58} or palette.gold
    timers.finaleArt.title(g,lost and 'DEFEAT' or 'VICTORY',
      w,h,titleY,reveal,rest*(.90+.10*zoom+.038*flare),trim)
    local rising=smoothstep((party-.26)/.52)
    local subtitleY=h*.215+h*.019*(1-rising)
    local label=teamNames[owner]:upper()..' KINGDOM WINS'
    local font=fonts.medium
    local labelWidth=math.min(w*.79,font:getWidth(label)*1.08)
    local edge=labelWidth*.5+8
    local lineY=subtitleY+fontHeight(font)*.57
    color(trim,.74*rising)
    g.setLineWidth(1.2)
    g.line(w*.5-edge-w*.047*rising,lineY,w*.5-edge,lineY)
    g.line(w*.5+edge,lineY,w*.5+edge+w*.047*rising,lineY)
    combatTitle(label,w*.5,subtitleY,w*.81,winnerTint,1.08,font,rising,true)
    for firework=1,lost and 0 or 4 do
      local flight=party-(firework-1)*.35
      local launch=.53
      local burst=flight-launch
      local keepX=x[owner]
      local insideY=base-size*.42
      local endX=keepX+w*((firework%2==0 and -.036 or .036)*(1+firework%3))
      local endY=base-h*(.18+(firework%3)*.035)
      if flight>=0 and burst<0 then
        for particle=1,8 do
          local p=math.max(0,(flight-particle*.030)/launch)
          local px=keepX+(endX-keepX)*p
          local py=insideY+(endY-insideY)*p
          g.setColor(1,.74,.34,.87*(1-particle/9))
          g.circle('fill',px,py,math.max(1.2,size*.016*(1.4-particle*.11)))
        end
      elseif burst>=0 and burst<1.03 then
        local spread=(1-(1-burst/1.03)^2)*w*.147
        for ray=1,18 do
          local angle=ray*math.pi*2/18+firework*.6
          local dx,dy=math.cos(angle),math.sin(angle)
          local px=endX+dx*spread
          local py=endY+dy*spread+h*.062*burst^2
          local gold=ray%3==0
          g.setColor(gold and 1 or winnerTint[1],gold and .77 or winnerTint[2],
            gold and .45 or winnerTint[3],.92*(1-burst/1.03))
          g.setLineWidth(1.45)
          g.line(px,py,px-dx*math.min(6,spread*.26),py-dy*math.min(6,spread*.26))
        end
      end
    end
  end
  if shakeScene then g.pop() end
  if t>=4.5 then text('Use the Zompa Back button to leave.',10,h*.92,w-20,'center',fonts.small) end
end

local ATTACK_NOTICE_TIME, QUICK_NOTICE_TIME, TURN_NOTICE_TIME = 1.64, 1.36, 1.06
local function attackNoticeDuration(view)
  return view.quick and QUICK_NOTICE_TIME or ATTACK_NOTICE_TIME
end
local function showTurn(openingTurn)
  overlay=not state.winner and {type='turnNotice',side=state.turn,elapsed=0,openingTurn=openingTurn} or nil
  if overlay and not openingTurn and (mode=='local' or mode=='solo' and state.turn==1
    or mode=='online' and state.turn==onlineSide) then playCue('turn') end
  timers.cpu=0
end

local function drawBoardNotice()
  local g=love.graphics
  local w,h=layout.w,layout.h
  local event=overlay.event
  local side=event and event.actor or overlay.side
  local colors,names=teamLabels,teamNames
  local function name(owner,class)
    return class=='wall' and 'Wall Section' or names[owner]..' '..rules.classes[class].name
  end
  if event then
    local ax,ay=center(event.from.r,event.from.c)
    local dx,dy=center(event.to.r,event.to.c)
    local size=layout.radius
    local function showFallen(class,owner,x,y)
      local sprite=unitArt[owner][class]
      if class=='fortress' then fortressArt(x,y,owner,size)
      elseif sprite then drawBadgeSprite(sprite,x,y,layout.scale) end
    end
    if event.defeated then showFallen(event.defenderClass,3-side,dx,dy) end
    if event.attackerDefeated then showFallen(event.attackerClass,side,ax,ay) end
    local strength=.75+.18*math.sin(overlay.elapsed*11)
    color(colors[side],strength);g.setLineWidth(math.max(2,size*.10))
    g.circle('line',ax,ay,size*.98)
    g.line(ax,ay,dx,dy)
    color(colors[3-side],strength);g.circle('line',dx,dy,size*.98)
    local arrowX,arrowY=ax+(dx-ax)*.65,ay+(dy-ay)*.65
    color(colors[side],1);g.circle('fill',arrowX,arrowY,math.max(2,size*.15))
  end

  local ww=math.min(w*.84,460)
  local hh=math.max(event and 85 or 65,math.min(event and 124 or 92,h*.24))
  local duration=event and attackNoticeDuration(overlay) or TURN_NOTICE_TIME
  local alpha=math.min(smoothstep(overlay.elapsed/.20),smoothstep((duration-overlay.elapsed)/.24))
  local x,y=(w-ww)*.5,timers.variantUI.boardDialogTop(layout,hh)
  if event then
    g.setColor(.02,.04,.07,.29*alpha);g.rectangle('fill',0,0,w,h)
  end
  g.setColor(.025,.04,.075,(event and .89 or .69)*alpha);g.rectangle('fill',x,y,ww,hh,12,12)
  color(colors[side],.87*alpha);g.setLineWidth(1.7)
  g.rectangle('line',x,y,ww,hh,12,12)
  if event then
    combatTitle(name(side,event.attackerClass)..' Attacks',w*.5,y+hh*.14,ww-18,colors[side],1,fonts.medium,alpha)
    local cx,ay=w*.5,y+hh*.47
    color(colors[side],.88*alpha);g.setLineWidth(1.7)
    g.line(cx-8,ay,cx+8,ay)
    g.line(cx+3,ay-4,cx+8,ay,cx+3,ay+4)
    combatTitle(name(3-side,event.defenderClass),w*.5,y+hh*.59,ww-18,
      event.wallHealth and palette.gold or colors[3-side],1,fonts.medium,alpha)
  else
    local name=overlay.openingTurn and playerName(side) or names[side]
    local label=name=='You' and 'Your Turn' or name.."'s Turn"
    local font=fonts.large
    local width=font.getWidth and font:getWidth(label) or #label*fontHeight(font)*.59
    local fit=math.min(1,(ww-26)/math.max(1,width))
    local passed=not overlay.openingTurn and state.last and state.last.type=='pass' and state.last.actor
    local titleY=passed and y+hh*.14 or y+(hh-fontHeight(font)*fit)*.5
    combatTitle(label,w*.5,titleY,ww-18,colors[side],fit,font,alpha)
    if passed then
      combatTitle(names[passed]..' passes: no legal action',w*.5,y+hh*.65,
        ww-18,palette.text,1,fonts.cardHint,alpha)
    end
  end
end
local function showEvent(event)
  selected,inspected,targets,intended=nil,nil,{},nil
  if event and event.resurrectionChoice then
    overlay={type='resurrectionChoice',event=event,elapsed=0}
    playCue('ready')
  elseif event and event.resurrection then
    overlay={type='resurrection',event=event,elapsed=0}
    playCue('initiative',.83)
  elseif event and event.trap then
    overlay={type='trap',event=event,elapsed=0}
    playCue('collapse')
    playHurt(event.trap.class)
  elseif event and event.potion then
    overlay={type='potion',event=event,elapsed=0}
    if event.potion.gained then playCue('heal')
    else playCue('breach',1.35) end
  elseif event and event.crate then
    overlay={type='crate',event=event,elapsed=0}
    playCue('select')
  elseif event and event.type=='attack' then
    local quick=(state.battleCount or 0)>1
    overlay={type='attackNotice',event=event,elapsed=0,quick=quick}
    if not quick and not event.deathMatch then playCue('ready') end
  elseif event and event.siege then
    overlay={type='siege',siege=event.siege,elapsed=0}
  elseif event then
    showTurn()
  end
end
-- Animate moves along their legal path. Attacks animate in the battle view.
-- The deterministic game state is already committed, so animation is visual only.
local function beginEvent(event,previous)
  selected,inspected,targets,intended=nil,nil,{},nil
  if event and event.type=='move' and previous then
    local route=event.route
    if route and #route>=2 then
      local unit=previous.units[event.id]
      moving=moveFx.new(event,unit.class)
      if event.trap or event.potion or event.crate or event.resurrection then moving.hpBeforeLanding=unit.hp end
      if event.resurrection then moving.pieceClass=unit.class end
      queuedEvent=event
      timers.cpu=0
      overlay=nil
      return
    end
  end
  showEvent(event)
end
local REWARD_PENDING, REWARD_SHOWN = 'REWARD:', 'REWARD_SHOWN:'
local startSave={brief='MATCH_BRIEF:',ready='ROLL_READY:',rolling='ROLLING:'}
local function sessionSave(stage)
  if mode=='online' then return end
  local ok,err
  if state.winner~=nil and not stage then ok,err=zompa.clearSession()
  else
    local data=rules.serialize(state)
    if stage then data=stage..data end
    ok,err=zompa.saveSession(data)
  end
  if not ok then print('Session save failed: '..tostring(err)) end
end
local function localAction(action,arrived)
  local previous=rules.copy(state)
  local ok,event=rules.apply(state,action)
  if not ok then notice=event;return false end
  sessionSave(event.heal and playerControlsReward(event.actor) and REWARD_PENDING)
  if arrived then showEvent(event) else beginEvent(event,previous) end
  return true
end
-- The host alternates starting with the inviter. Two setup tokens establish
-- a shared seed, then Red yields the first host slot if Blue won the roll.
local function unwrapOnline(raw)
  local nonces,encoded={}
  for i=1,2 do
    local value=raw[i]:match('^I(%d+)$')
    if i==1 and not value then value,encoded=raw[i]:match('^I(%d+)_([0-9_BCGMQ]+)$') end
    local number=value and #value<=10 and tonumber(value)
    if not number or number<1 or number>2147483646 then return nil,'Invalid opening roll.' end
    nonces[i]=number
  end
  local seed=(nonces[1]*181+nonces[2]*9973)%2147483647
  if seed==0 then seed=1 end
  local opening=rules.initiative(seed)
  local start=3
  if opening.first==2 then
    if raw[3] and raw[3]~='Y' then return nil,'Invalid opening handoff.' end
    start=4
  end
  local tokens,phase=require('online_flow').parse(raw,start)
  if not tokens then return nil,phase end
  local options=timers.variants.decode(encoded)
  if not options then return nil,'Invalid match options.' end
  return tokens,seed,opening,phase,options
end

local function sendHostTurn(token,outcome)
  local sent,err=zompa.submitTurn(token,outcome)
  turnSendFailed=not sent
  if sent then pending=true;notice='Sending turn…' else notice=tostring(err) end
  return sent
end

function timers.rememberOnlineHistory(history)
  lastOnlineCount=#history
  timers.onlinePrefix=history
end

function timers.resetOnlineBoard()
  -- Drop presentation and pending commands along with the discarded history.
  lastOnlineCount=-1
  timers.onlinePrefix,timers.onlineStart,timers.resurrectionArrival=nil,nil,nil
  timers.onlineStarted,timers.onlineStartAcknowledged=false,false
  onlineReady,pending,turnSendFailed=false,false,false
  selected,inspected,targets,intended,inspectedFortOwner=nil,nil,{},nil,nil
  moving,queuedEvent,cardBox=nil,nil,nil
  actionBox,cancelBox=nil,nil
  finishElapsed=0
  detail.piece=nil
  intro,overlay={},nil
  timers.settings={options=timers.variants.defaults()}
  timers.useBoard('classic')
  state=rules.new(47061)
end

local function readOnline()
  local history,side,allowed=zompa.readTurns()
  if not history then onlineAllowed=false;return end
  onlineSide=side
  local startOptions=history[1] and history[1]:match('^S_(.+)$')
  local hasStart=history[1]=='S' or startOptions~=nil
  local offset=hasStart and 2 or 0
  local hadStart=timers.onlineStart
  if hadStart and (history[1]~=hadStart or timers.onlineStartAcknowledged and history[2]~='K') then
    timers.resetOnlineBoard()
  else
    for index,token in ipairs(timers.onlinePrefix or {}) do
      if history[index+offset]~=token then
        timers.resetOnlineBoard()
        break
      end
    end
  end
  if hasStart then
    timers.onlineStarted=true
    timers.onlineStart=history[1]
    timers.onlineStartAcknowledged=history[2]=='K'
    local chosen=timers.variants.decode(startOptions)
    if not chosen then blocked='Invalid match options.';onlineAllowed=false;return end
    if #history<=3 and not onlineReady and state.moves==0 then
      timers.settings.options=chosen
      if not timers.settings.review then timers.settings.open=false end
      if state.boardId~=chosen.board or state.options.wall~=chosen.wall then
        if intro and intro.help and chosen.board~='classic' then detail.piece=nil;intro=nil end
        timers.useBoard(chosen.board)
        state=rules.new(47061,1,{wall=chosen.wall,wallHealth=chosen.wallHealth,wallShield=chosen.wallShield,
          legacyBridgeWall=chosen.legacyBridgeWall,legacyFlankWall=chosen.legacyFlankWall})
      end
    end
    if intro and not intro.help then intro=nil end
    if #history==1 then
      onlineAllowed=false
      lastOnlineCount=-2
      if side==2 and allowed and not pending then sendHostTurn('K') end
      return
    end
    if history[2]~='K' then blocked='Invalid start handoff.';return end
    table.remove(history,1)
    table.remove(history,1)
    if lastOnlineCount==-2 then lastOnlineCount=-1;pending=false end
  end
  -- Consume queued packets in order so a delayed client sees each reveal.
  local liveCount=#history
  if lastOnlineCount>=0 and liveCount>lastOnlineCount+1 then
    for i=liveCount,lastOnlineCount+2,-1 do history[i]=nil end
  end
  local incoming=history[#history]
  if lastOnlineCount>=0 and #history>lastOnlineCount and overlay then
    if incoming~='K' and incoming~=timers.resurrectionArrival and not (overlay.type=='battle' and (incoming=='R' or incoming=='C') and (overlay.ready or (overlay.event.actor==side and pending))) then return end
  end
  onlineAllowed=allowed and #history==liveCount
  local oldCount=lastOnlineCount
  if #history~=oldCount then pending,turnSendFailed=false,false end
  if lastOnlineCount==-2 and #history==0 then onlineAllowed=false;return end
  if #history<2 then
    blocked=nil
    onlineReady=false
    timers.rememberOnlineHistory(history)
    -- The inviter starts setup by tapping Roll. The invitee contributes
    -- their nonce automatically after receiving that first host turn.
    if #history==1 and intro and not intro.help then intro=nil end
    if #history==1 and side==2 and onlineAllowed and not pending then
      sendHostTurn('I'..tostring(love.math.random(1,2147483646)))
    end
    return
  end
  if #history==oldCount and not blocked then
    if onlineAllowed and not pending and (incoming=='R' or (incoming and incoming:match('^[AD]%d'))) then
      sendHostTurn('K')
    elseif state.first==2 and #history==2 and onlineAllowed and side==1 and not pending then
      sendHostTurn('Y')
    end
    return
  end
  local tokens,seed,opening,phase,options=unwrapOnline(history)
  if not tokens then blocked=seed;onlineAllowed=false;return end
  if startOptions and timers.variants.encode(options)~=startOptions then
    blocked='Match options changed after setup.';onlineAllowed=false;return
  end
  if oldCount>=2 and (incoming=='K' or incoming=='R' or incoming=='C') then
    timers.rememberOnlineHistory(history)
    if incoming=='R' and overlay then
      overlay.bonusElapsed=0
      overlay.ready=false
      overlay.button=nil
    elseif incoming=='C' and overlay then
      if overlay.event.siege then overlay={type='siege',siege=overlay.event.siege,elapsed=0}
      else showTurn() end
    end
    return
  end
  local synced,err
  if onlineReady and oldCount>=2 and #history==oldCount+1 and incoming==tokens[#tokens] then
    local action=rules.decode(incoming)
    if action then
      synced=rules.copy(state)
      local ok,result=rules.apply(synced,action)
      if not ok then synced,err=nil,result end
    else err='Malformed turn.' end
  else
    synced,err=timers.rulebook.replay(seed,tokens,opening.first,nil,nil,nil,nil,false,options)
  end
  if not synced then blocked=err;onlineAllowed=false;return end
  blocked=nil
  onlineReady=true
  if timers.settings.review then timers.settings.open,timers.settings.review=false,nil end
  local previous=state
  if intro and intro.help and synced.boardId~='classic' then detail.piece=nil;intro=nil end
  timers.useBoard(synced.boardId)
  state=synced
  timers.rememberOnlineHistory(history)
  if #tokens==0 and oldCount<2 then
    if intro and not intro.help then intro=nil end
    overlay={type='opening',opening=opening,elapsed=0}
    if options.crates or options.wall or options.resurrection then overlay={type='brief',next=overlay} end
  elseif oldCount<0 and phase then
    intro=nil
    overlay={type='battle',event=synced.last,elapsed=0}
    if phase=='reward' or phase=='healed' then overlay.bonusElapsed=0 end
  elseif synced.last and #history==oldCount+1 then
    intro=nil
    if incoming==timers.resurrectionArrival then
      timers.resurrectionArrival=nil
      showEvent(synced.last)
    else
      beginEvent(synced.last,previous)
    end
  else
    if #tokens>0 then intro=nil end
    showEvent(nil)
  end
end

local function sendOnline(action)
  if pending or not onlineReady or not onlineAllowed or state.turn~=onlineSide then return end
  local tentative=rules.copy(state)
  local ok,result=rules.apply(tentative,action)
  if not ok then notice=result;return false end
  local outcome=tentative.winner
  if action.type=='attack' then outcome=nil end
  return sendHostTurn(rules.encode(action,result),outcome)
end
local function mayAct()
  return state and state.winner==nil and not overlay and not moving and not blocked and
    (mode=='online' and onlineReady and onlineAllowed and state.turn==onlineSide and not pending or
    mode=='solo' and state.turn==1 or mode=='local')
end
local function drawActionBar()
  actionBox,cancelBox=nil,nil
  timers.potionAttackBox=nil
  local x,y,w,h=6,layout.actionY,layout.w-12,layout.actionH
  if intended and selected and mayAct() then
    local isAttack=intended.type~='move'
    local gap=math.min(8,w*.032)
    local available=w-gap*(intended.destroyPotion and 2 or 1)
    local confirmW=available*(intended.destroyPotion and .38 or .74)
    local label=intended.type=='crate' and 'DESTROY CRATE' or intended.type=='potion' and 'DESTROY POTION'
      or isAttack and 'ATTACK NOW' or 'MOVE HERE'
    luxeButton(label,x,y,confirmW,h,isAttack)
    actionBox={x=x,y=y,w=confirmW,h=h}
    local cancelX=x+confirmW+gap
    if intended.destroyPotion then
      local attackW=available*.37
      luxeButton(intended.destroyPotion=='crate' and 'DESTROY CRATE' or 'DESTROY POTION',cancelX,y,attackW,h,true)
      timers.potionAttackBox={x=cancelX,y=y,w=attackW,h=h}
      cancelX=cancelX+attackW+gap
    end
    luxeButton('CANCEL',cancelX,y,x+w-cancelX,h,'neutral')
    cancelBox={x=cancelX,y=y,w=x+w-cancelX,h=h}
    if turnSendFailed then
      text('Could not send. Tap again to retry.',x,y+h+5,w,'center',fonts.small)
    end
  else
    local label
    if mode=='online' and not onlineReady then label='WAITING FOR OPENING ROLL'
    elseif pending then label='SENDING TURN…'
    elseif turnSendFailed then label='COULD NOT SEND TURN'
    elseif overlay and overlay.type=='resurrectionChoice' then label='CHOOSE A WARRIOR'
    elseif overlay and overlay.type=='resurrection' then label='SOLDIER RESURRECTION'
    elseif overlay and overlay.type=='attackNotice' then
      label=overlay.event.actor==1 and 'RED ATTACKS' or 'BLUE ATTACKS'
    elseif moving then label=moving.event.actor==2 and 'BLUE KINGDOM MOVES' or 'RED KINGDOM MOVES'
    elseif mode=='solo' and state.turn==2 then label='BLUE KINGDOM IS THINKING…'
    elseif selected and rules.piece(state,selected).class=='fortress' and not next(targets.attacks) then
      label='NO ENEMIES IN BOULDER RANGE'
    elseif selected then label='TAP A HIGHLIGHTED HEX'
    elseif saveVersionChanged and state.moves==0 then label='RULES UPDATED  •  START A NEW MATCH'
    elseif state.moves==0 and mayAct() then label='TAP ONE OF YOUR UNITS'
    else
      local nextSide=state.turn==1 and 'RED' or 'BLUE'
      local waiting=mode=='online' and state.turn~=onlineSide
      label=nextSide..' TURN  •  '..(waiting and 'WAITING' or 'CHOOSE A PIECE')
    end
    love.graphics.setColor(.11,.15,.17,.96)
    love.graphics.rectangle('fill',x,y,w,h,9,9)
    frame(x+.5,y+.5,w-1,h-1,.65,9)
    color(palette.text);love.graphics.setFont(fonts.small)
    love.graphics.printf(label,x+4,y+(h-fontHeight(fonts.small))*.5,w-8,'center')
  end
end
local function actorAction(action)
  if not mayAct() then return end
  if action.type=='move' and rules.resurrectionMove(state,state.units[action.id],action.r,action.c) then
    local route=rules.route(state,action.id,action.r,action.c)
    if not route then return false end
    local unit=state.units[action.id]
    beginEvent({type='move',actor=unit.owner,id=unit.id,from=route[1],to={r=action.r,c=action.c},
      route=route,resurrectionChoice=action},state)
    return true
  end
  if mode=='online' then return sendOnline(action) end
  return localAction(action)
end
local function computerAction()
  if state.winner~=nil or state.turn~=2 or overlay or moving then return end
  local action=chooseCpuAction(state,love.math.random)
  if action then localAction(action) end
end
local function inside(box,x,y)
  return box and x>=box.x and y>=box.y and x<=box.x+box.w and y<=box.y+box.h
end
local function closePractice()
  intro.help=nil
  if timers.onlineStarted or (overlay and overlay.type=='opening' and overlay.elapsed) then intro=nil end
end

function timers.openSetup()
  intro.help=nil
  timers.settings.open=true
  timers.settings.dropdown=false
  timers.settings.hits=nil
  timers.settings.error=nil
  playCue('select')
end

function timers.backFromOpening()
  if mode=='online' then
    -- Keep the synchronized setup and committed roll intact while reviewing locally.
    timers.settings.review=true
    timers.settings.open=true
    timers.settings.dropdown=false
    timers.settings.hits=nil
    timers.settings.error=nil
  elseif overlay.type=='opening' and (state.options.crates or state.options.wall or state.options.resurrection) then
    overlay={type='brief',next=overlay}
    sessionSave(startSave.brief)
  else
    local boardId=state.boardId
    if boardId=='corners-legacy' then boardId='corners' end
    if boardId=='bridges-legacy' then boardId='bridges' end
    if boardId=='narrows-previous' or boardId=='narrows-legacy' then boardId='narrows' end
    local options=timers.variants.defaults(boardId)
    for _,name in ipairs({'wall','wallHealth','wallShield','overWall','crates','crateCount','destroyCrates','resurrection'}) do
      options[name]=state.options[name]
    end
    options.crateCount=math.min(options.crateCount,6)
    timers.settings.options=options
    timers.settings.preview=nil
    intro={}
    introTime=introDuration
    timers.openSetup()
  end
end

local function startMatch()
  local setup=timers.settings
  local options=setup.options
  if mode=='online' then
    if onlineSide~=1 or pending or not onlineAllowed or lastOnlineCount~=0 then
      setup.error='Waiting for the invitation to sync.'
      return
    end
    local suffix=timers.variants.enabled(options) and '_'..timers.variants.encode(options) or ''
    if not sendHostTurn('S'..suffix) then
      setup.error='Could not start. Tap Continue to retry.'
      return
    end
    lastOnlineCount=-2
    onlineAllowed=false
    timers.useBoard(options.board)
    state=rules.new(state.seed,state.first,{wall=options.wall,wallHealth=options.wallHealth,wallShield=options.wallShield,
      legacyFlankWall=options.legacyFlankWall})
  else
    timers.useBoard(options.board)
    local opening=rules.initiative(state.seed)
    state=rules.new(state.seed,opening.first,options)
    overlay={type='opening',opening=opening}
    if options.crates or options.wall or options.resurrection then overlay={type='brief',next=overlay} end
    sessionSave(overlay.type=='brief' and startSave.brief or startSave.ready)
  end
  setup.open=false
  intro=nil
  playCue('siege-horn')
end

local function tapPractice(practice,x,y)
  if practice.expanded then
    detail.tap(x,y)
    if not detail.piece then practice.expanded=nil;practice.step='complete' end
    return
  end
  if inside(intro.close,x,y) then closePractice();return end
  if practice.animation then return end
  local battle=practice.battle
  if battle then
    if inside(battle.button,x,y) then
      battle.button=nil
      if battle.bonusElapsed then
        practice.battle=nil
        practice.step='objective'
      else
        battle.bonusElapsed=0
      end
    end
    return
  end
  local step,board=practice.step,practice.board
  local cell=xyToCell(x,y)
  local clicked=cell and rules.occupied(board,cell.r,cell.c)
  local id=clicked and clicked.ref.id
  if step=='inspect' and id==PRACTICE_SOLDIER then
    practice.step,practice.stat='stats',1
  elseif step=='stats' and inside(practice.button,x,y) then
    if practice.stat<#practiceStats then
      practice.stat=practice.stat+1
    else
      practice.step='move'
    end
  elseif (step=='move' or step=='confirmMove') and cell
      and rules.moves(board,PRACTICE_SOLDIER)[rules.key(cell.r,cell.c)] then
    practice.destination=cell
    practice.step='confirmMove'
  elseif step=='confirmMove' and inside(practice.button,x,y) then
    local to=practice.destination
    local moved,event=rules.apply(board,{type='move',id=PRACTICE_SOLDIER,r=to.r,c=to.c})
    if moved then
      board.turn=1
      practice.step='moving'
      practice.animation=moveFx.new(event,'soldier')
    end
  elseif step=='archer' and id==PRACTICE_ARCHER then
    board.units[PRACTICE_FOE].hp=6
    practice.step='target'
  elseif step=='target' and id==PRACTICE_FOE then
    practice.step='confirmAttack'
    practice.selectedAt=animationTime
  elseif step=='confirmAttack' and inside(practice.button,x,y) then
    local foe=board.units[PRACTICE_FOE]
    local attacked,event=rules.apply(board,{type='attack',id=PRACTICE_ARCHER,r=foe.r,c=foe.c})
    if attacked then
      practice.battle={event=event,elapsed=0}
    end
  elseif step=='objective' and clicked and clicked.ref==board.forts[2] then
    practice.step='expand'
  elseif step=='expand' and cardBox and inside(cardBox.expand,x,y) then
    practice.expanded=true
    practice.openedAt=animationTime
  elseif step=='complete' and inside(practice.button,x,y) then
    if mode=='online' and onlineSide~=1 then closePractice() else timers.openSetup() end
  end
end

local function onTap(x,y)
  if not state then return end
  if detail.piece and not intro then detail.tap(x,y);return end
  if moving then return end
  if intro then
    if intro.help then tapPractice(intro.help,x,y)
    elseif inside(intro.guide,x,y) then intro.help=startPractice()
    elseif (mode~='online' or onlineSide==1) and inside(intro.start,x,y) then timers.openSetup()
    end
    return
  end
  if mode=='online' and not onlineReady and not overlay then
    if onlineSide==1 and onlineAllowed and not pending and lastOnlineCount==0 then
      if inside(onlineOpeningPrompt.backButton,x,y) then timers.backFromOpening();return end
      if not inside(onlineOpeningPrompt.button,x,y) then return end
      local options=timers.settings.options
      local suffix=timers.variants.enabled(options) and '_'..timers.variants.encode(options) or ''
      sendHostTurn('I'..tostring(love.math.random(1,2147483646))..suffix)
    end
    return
  end
  if overlay then
    if overlay.type=='resurrectionChoice' then
      if not pending and overlay.choices then
        for i,box in ipairs(overlay.choices) do
          if inside(box,x,y) then
            local action=overlay.event.resurrectionChoice
            action.resurrection=rules.resurrectionClasses[i] and i or nil
            if mode=='online' then
              if sendOnline(action) then timers.resurrectionArrival=rules.encode(action) end
            else localAction(action,true) end
            return
          end
        end
      end
      return
    end
    if overlay.type=='resurrection' then return end
    if mode=='online' and overlay.type=='battle' then
      if overlay.event.actor==onlineSide and onlineAllowed and not pending and inside(overlay.button,x,y) then
        if overlay.event.heal and not overlay.bonusElapsed then sendHostTurn('R')
        else sendHostTurn('C',state.winner) end
      end
      return
    end
    if inside(overlay.backButton,x,y) and (overlay.type=='brief' or overlay.type=='opening' and not overlay.elapsed) then
      timers.backFromOpening()
      return
    end
    if not inside(overlay.button,x,y) then return end
    if overlay.type=='brief' then
      overlay=overlay.next
      sessionSave(startSave.ready)
    elseif overlay.type=='opening' then
      overlay.elapsed=0
      overlay.button,overlay.backButton=nil,nil
      sessionSave(startSave.rolling)
    elseif overlay.event.heal and not overlay.bonusElapsed then
      overlay.bonusElapsed=0
      overlay.button=nil
    else
      if overlay.event.heal and playerControlsReward(overlay.event.actor) then sessionSave() end
      if overlay.event.siege then overlay={type='siege',siege=overlay.event.siege,elapsed=0}
      else showTurn() end
    end
    return
  end
  if state.winner~=nil then return end
  if cardBox and inside(cardBox.expand,x,y) then
    detail.piece=cardBox.piece
    detail.started=animationTime
    return
  end
  if inside(cardBox,x,y) then return end
  if selected and intended and inside(cancelBox,x,y) then
    intended=nil
    turnSendFailed=false
    local piece=rules.piece(state,selected)
    inspected=piece.class=='fortress' and 'fort' or selected
    if piece.class=='fortress' then inspectedFortOwner=piece.owner end
    notice='Destination cleared. Pick another hex.'
    return
  end
  if intended and selected and mayAct() and (inside(actionBox,x,y)
    or intended.destroyPotion and inside(timers.potionAttackBox,x,y)) then
    local kind=inside(timers.potionAttackBox,x,y) and intended.destroyPotion or intended.type
    local action={type=kind,id=selected,r=intended.r,c=intended.c}
    -- The rules validate again when the action is committed.
    notice=''
    if actorAction(action) then intended=nil end
    return
  end
  local cell=xyToCell(x,y)
  if not cell then return end
  turnSendFailed=false
  local t=rules.occupied(state,cell.r,cell.c)
  local key=rules.key(cell.r,cell.c)
  if t and t.owner==state.turn and mayAct() and (t.kind=='unit' or t.ref.armed) then
    -- Choosing a different friendly soldier cancels the pending action.
    if selected~=t.ref.id then selectionAge=0;playCue('select') end
    selected,intended=t.ref.id,nil
    inspected=t.kind=='fort' and 'fort' or selected
    if t.kind=='fort' then inspectedFortOwner=t.owner end
    targets={moves=rules.moves(state,selected),attacks=rules.attacks(state,selected),crossed={}}
    if t.ref.class=='wizard' then
      for key in pairs(targets.moves) do
        local r,c=rules.fromkey(key)
        for crossed in pairs(rules.jumpOver(state,selected,r,c)) do targets.crossed[crossed]=true end
      end
    end
    notice='Gold: move. Icy blue: attack.'
    return
  end
  if selected and mayAct() then
    local attack=(targets.attacks or {})[key]
    local move=(targets.moves or {})[key]
    local itemAttack=attack and (attack.kind=='potion' or attack.kind=='crate') and attack.kind
    local kind=attack and not itemAttack and 'attack' or move and 'move' or itemAttack or nil
    if kind then
      if not intended or intended.r~=cell.r or intended.c~=cell.c then playCue('target') end
      intended={type=kind,r=cell.r,c=cell.c,destroyPotion=kind=='move' and itemAttack,
        crossed=kind=='move' and rules.jumpOver(state,selected,cell.r,cell.c) or {}}
      if kind=='move' then intended.route=rules.route(state,selected,cell.r,cell.c)
      else
        intended.selectedAt=animationTime
        intended.deathMatch=kind=='attack' and t.kind~='wall' and rules.isDeathMatch(rules.piece(state,selected),t.ref)
      end
      inspected=t and t.kind=='unit' and t.ref.id or t and t.kind=='fort' and 'fort'
        or t and t.kind=='wall' and 'wall' or state.potions[key] and 'potion'
        or state.crates[key] and 'crate' or selected
      if t and t.kind=='fort' then inspectedFortOwner=t.owner end
      if inspected=='wall' then timers.inspectedWall=key end
      if inspected=='potion' or inspected=='crate' then timers.inspectedPotion=key end
      if kind=='attack' then
        local name=t.kind=='wall' and 'Wall Section' or rules.classes[t.ref.class].name
        notice='TARGET '..name:upper()..'  •  Confirm ATTACK'
      elseif itemAttack and not move then
        notice='Confirm destruction of the marked crate or potion.'
      else
        notice='Confirm move to the marked hex.'
      end
      return
    end
  end
  intended=nil
  if t and t.kind=='unit' then
    -- Enemy inspection never moves or attacks and does not deselect the friendly unit.
    inspected=t.ref.id
    if t.owner~=state.turn then
      notice=selected and 'Enemy is out of attack range.' or 'Enemy inspected. Select a warrior first.'
    end
  elseif t and t.kind=='fort' then
    inspected='fort'
    inspectedFortOwner=t.owner
    notice=t.owner==state.turn and 'Protect your Fortress.' or 'Enemy Fortress inspected.'
  elseif t and t.kind=='wall' then
    inspected='wall'
    timers.inspectedWall=key
  elseif state.potions[key] or state.crates[key] then
    inspected=state.crates[key] and 'crate' or 'potion'
    timers.inspectedPotion=key
  elseif selected then
    local piece=rules.piece(state,selected)
    inspected=piece.class=='fortress' and 'fort' or selected
    if piece.class=='fortress' then inspectedFortOwner=piece.owner end
    notice='This hex is not reachable by the selected soldier.'
  else
    inspected=nil
    notice='Select a warrior first.'
  end
end
local lastTapAt=-10
local function touch(x,y)
  local now=love.timer.getTime()
  if now-lastTapAt<0.09 then return end
  lastTapAt=now
  if timers.settings.open then
    local action=timers.variantUI.tapSetup(timers.settings,x-layout.stageX,y)
    if timers.settings.review then
      if action=='continue' then timers.settings.open,timers.settings.review=false,nil end
    elseif action=='back' then timers.settings.open=false
    elseif action=='continue' then startMatch() end
    return
  end
  if intro and not intro.help and introTime<introDuration then introTime=introDuration; return end
  onTap(x-layout.stageX,y)
end
local function fitHostedWindow()
  if not love.system or love.system.getOS()~='Web' then return end
  local window=love.window
  local screenW,screenH=window.getDesktopDimensions()
  if screenW<=0 or screenH<=0 then return end
  -- LÖVE Web reports the display dimensions. Zompa hosts this canvas below
  -- its toolbar and above Android's navigation area.
  local hostChrome=math.max(112,math.ceil(screenH*.15))
  local banner=zompa.mode()=='online' and 52 or 0
  local availableH=math.max(160,screenH-hostChrome-banner)
  local viewport=io.open('/zompado/viewport','rb')
  if viewport then
    local raw=viewport:read(32)
    viewport:close()
    local vw,vh=tostring(raw):match('^(%d+):(%d+)$')
    if vw and tonumber(vw)>=120 and tonumber(vh)>=160 then
      screenW,availableH=tonumber(vw),tonumber(vh)
    end
  end
  local w=math.min(screenW,600,math.floor(availableH*.76))
  local h=math.min(availableH,math.floor(w*1.88))
  if timers.viewportW==w and timers.viewportH==h then return end
  timers.viewportW,timers.viewportH=w,h
  window.setMode(w,h,{resizable=true,minwidth=120,minheight=160})
end
function love.load()
  detail.piece=nil
  timers.viewportW,timers.viewportH,timers.onlineStarted,timers.onlinePrefix=nil,nil,false,nil
  fitHostedWindow()
  if not score and love.audio and mixer.register then
    local loaded,source=pcall(love.audio.newSource,'audio/standard-of-the-two-kingdoms.ogg','stream')
    if loaded then
      source:setLooping(true)
      source:setVolume(.54 * .80)
      score=mixer:register(source,'music')
      score:play()
    end
  end
  if love.graphics.newImage then
    timers.finaleArt.load(love.graphics)
    timers.projectiles.load(love.graphics)
    -- The hosted WebGL runtime cannot mipmap these non-power-of-two sprites.
    local mipmaps=not love.system or love.system.getOS()~='Web'
    loadFieldArt(mipmaps)
    timers.variantUI.loadArt(love.graphics)
    local okLogo,image=pcall(love.graphics.newImage,'art/fortress-siege-logo.png')
    if okLogo then logo=image end
    local okArena,backdrop=pcall(love.graphics.newImage,'art/battle-arena.png')
    if okArena then arena=backdrop end
    local okValley,landscape=pcall(love.graphics.newImage,'art/siege-valley.jpg')
    if okValley then valley=landscape end
    local ok,img=pcall(love.graphics.newImage,'art/board.png')
    if ok and img then artBoard=img; if img.setFilter then img:setFilter('linear','linear') end end
    for owner=1,2 do
      local okKeep,keep=pcall(love.graphics.newImage,('art/siege-keep-%d.png'):format(owner))
      if okKeep and keep then
        siegeKeeps[owner]=keep
        if love.graphics.newQuad then
          local iw,ih=keep:getDimensions()
          local quads={}
          for row=0,3 do
            for col=0,3 do
              quads[#quads+1]=love.graphics.newQuad(col*iw/4,row*ih/4,iw/4,ih/4,iw,ih)
            end
          end
          siegeChunks[owner]=quads
        end
      end
      for name,_ in pairs(rules.classes) do
        if name~='fortress' then
          local ok2,sp=pcall(love.graphics.newImage,('art/%s-%d.png'):format(name,owner))
          if ok2 and sp then
            unitArt[owner][name]=sp
            if sp.setFilter then sp:setFilter('linear','linear') end
          end
          local ok3,bust=pcall(love.graphics.newImage,('portraits/%s-%d.png'):format(name,owner))
          if ok3 and bust then
            portraitArt[owner][name]=bust
            if bust.setFilter then bust:setFilter('linear','linear') end
          end
          local fighterPath=('fighters/%s-%d.png'):format(name,owner)
          local ok5,fighter=pcall(love.graphics.newImage,fighterPath,{mipmaps=mipmaps})
          if not ok5 then ok5,fighter=pcall(love.graphics.newImage,fighterPath) end
          if ok5 and fighter then
            fighterArt[owner][name]=fighter
            if fighter.setFilter then fighter:setFilter('linear','linear') end
            -- Smaller battle views need filtered levels as the sprites rotate.
            if mipmaps and fighter.setMipmapFilter and fighter:getMipmapCount()>1 then
              fighter:setMipmapFilter('linear')
            end
          end
        end
        end
      local ok4,fort=pcall(love.graphics.newImage,('art/fortress-%d.png'):format(owner))
      if ok4 and fort then
        fortArt[owner]=fort
        if fort.setFilter then fort:setFilter('linear','linear') end
      end
    end
  end
  if not horn and love.audio and mixer.register then
    for _,name in ipairs({'siege-horn','select','land','archer','wizard','ogre','barbarian',
      'assassin','soldier','fortress','blocked','critical','breach','collapse',
      'move-soldier','move-archer','move-assassin','move-wizard','move-barbarian','move-ogre',
      'dice-roll','initiative','roll-tie','turn','target','ready','swing','loose-arrow','cast','boulder-launch',
      'defeat','duel','reward-ready','heal','full-health','victory','firework',
      'hurt-1','hurt-2','hurt-3','hurt-4'}) do
      local loaded,source=pcall(love.audio.newSource,'audio/'..name..'.wav','static')
      if loaded then cues[name]=mixer:register(source,'effects') end
    end
    horn=cues['siege-horn']
  end
  mode=zompa.mode()
  timers.settings={options=timers.variants.defaults()}
  rules=timers.rulebook
  local seed=mode=='online' and 47061 or love.math.random(1,2147483600)
  local opening=mode~='online' and rules.initiative(seed) or nil
  state=rules.new(seed,opening and opening.first)
  saveVersionChanged=false
  local resumeReward,rewardShown,resumeOpening=false,false,nil
  if mode~='online' then
    local saved=zompa.loadSession()
    if saved then
      local revealed=saved:match('^'..REWARD_SHOWN..'(.*)$')
      local rewardSave=revealed or saved:match('^'..REWARD_PENDING..'(.*)$')
      local startBody
      for phase,prefix in pairs(startSave) do
        if saved:sub(1,#prefix)==prefix then
          startBody=saved:sub(#prefix+1)
          resumeOpening=phase
          break
        end
      end
      local restored,err=rules.restore(rewardSave or startBody or saved)
      local recoveredRoll=restored and resumeOpening and rules.initiative(restored.seed)
      if recoveredRoll and (restored.moves~=0 or recoveredRoll.first~=restored.first) then
        restored,err=nil,'Invalid opening save.'
      end
      if restored then
        state=restored
        rules=timers.rulebook.forBoard(state.boardId)
        resumeReward=rewardSave and state.last and state.last.heal
        rewardShown=revealed~=nil
        opening=recoveredRoll
      else
        resumeOpening=nil
        saveVersionChanged=err=='Unrecognized save version.'
        print('Ignoring invalid saved session: '..tostring(err))
      end
    end
  end
  selected,inspected,targets,pending,overlay,intended,inspectedFortOwner=nil,nil,{},false,nil,nil,nil
  moving,queuedEvent,cardBox=nil,nil,nil
  actionBox,cancelBox=nil,nil
  notice,blocked,turnSendFailed='',nil,false
  intro=(opening and not resumeOpening or mode=='online') and {} or nil
  introTime=0
  if opening then
    overlay={type='opening',opening=opening,elapsed=resumeOpening=='rolling' and 0 or nil}
    if resumeOpening=='brief' then overlay={type='brief',next=overlay} end
  elseif resumeReward then
    overlay={type='battle',event=state.last,elapsed=COMBAT_READY_TIME+RESULT+REWARD_REVEAL+REWARD_FADE+.24,
      bonusElapsed=rewardShown and BONUS_TIME+BONUS_HOLD+.24 or nil}
  elseif state.last and state.last.trap then
    overlay={type='trap',event=state.last,elapsed=0}
  elseif state.last and state.last.potion then
    overlay={type='potion',event=state.last,elapsed=0}
  elseif state.last and state.last.crate then
    overlay={type='crate',event=state.last,elapsed=0}
  elseif state.last and state.last.siege then
    overlay={type='siege',siege=state.last.siege,elapsed=0}
  end
  finishElapsed=0
  animationTime=0
  selectionAge=0
  timers.cpu,timers.poll=0,0
  onlineSide,onlineAllowed,onlineReady,lastOnlineCount=nil,false,false,-1
  timers.onlineStart,timers.onlineStartAcknowledged,timers.resurrectionArrival=nil,false,nil
  onlineOpeningPrompt={}
  reflow(love.graphics.getDimensions())
  tileCanvas=nil
  if intro then prepareTileCanvas() end
end
function love.resize(w,h)
  if timers.settings then timers.settings.hits=nil end
  if intro then intro.surface=nil end
  tileCanvas=nil
  reflow(w,h)
end
function love.update(dt)
  timers.viewportPoll=(timers.viewportPoll or 0)+dt
  if timers.viewportPoll>=1 then timers.viewportPoll=0;fitHostedWindow() end
  mixer:update(dt)
  if score then
    scoreCheck=scoreCheck+dt
    if scoreCheck>=1 then
      scoreCheck=0
      if score:isPlaying() then
        scorePosition=score:tell()
      elseif score:getVolume()>0 then
        score:seek(scorePosition)
        score:play()
      end
    end
  end
  animationTime=animationTime+dt
  selectionAge=math.min(.16,selectionAge+dt)
  if mode=='online' then
    timers.poll=timers.poll+dt
    -- Let the current event finish before a newer turn can replace its animation or dialog.
    local canPoll=not overlay or overlay.type=='battle' or overlay.type=='attackNotice'
      or overlay.type=='resurrectionChoice' and pending
    if timers.poll>=0.34 and not moving and canPoll then
      timers.poll=0
      readOnline()
    end
  end
  if timers.settings.open then return end
  if intro and not blocked then
    introTime=introTime+dt
    if introTime>=introDuration then intro.surface=nil end
    local practice=intro.help
    local animation=practice and practice.animation
    if animation then
      if moveFx.update(animation,dt,playCue) then
        practice.animation=nil
        practice.board.units[PRACTICE_ARCHER].hp=3
        practice.step='archer'
      end
    end
    local battle=practice and practice.battle
    if battle then
      local before=battle.elapsed
      battle.elapsed=before+dt
      playBattleCues(battle,before)
      if battle.bonusElapsed then
        local beforeBonus=battle.bonusElapsed
        battle.bonusElapsed=beforeBonus+dt
        playRewardCues(beforeBonus,battle.bonusElapsed)
      end
    end
    return
  end
  local finishedMove=false
  if moving then
    if moveFx.update(moving,dt,playCue) then
      moving=nil
      local ev=queuedEvent;queuedEvent=nil
      if ev then showEvent(ev);finishedMove=true end
    end
  end
  if overlay and not finishedMove then
    local before=overlay.elapsed
    local cinematic=overlay.type=='siege' or overlay.type=='battle' and overlay.event.deathMatch
    if before then overlay.elapsed=before+dt*(cinematic and CINEMATIC_SPEED or 1) end
    if overlay.type=='opening' then
      if before then
        local index=math.floor(overlay.elapsed/OPENING.beat)+1
        local rolls=overlay.opening.rounds[index]
        if rolls then
          local start=(index-1)*OPENING.beat
          crossedCue(before,overlay.elapsed,start+.025,'dice-roll')
          crossedCue(before,overlay.elapsed,start+OPENING.land,'land')
          crossedCue(before,overlay.elapsed,start+1.03,rolls[1]==rolls[2] and 'roll-tie' or 'initiative')
        end
      end
      local resultEnd=(#overlay.opening.rounds-1)*OPENING.beat+OPENING.land+OPENING.resultHold
      if overlay.elapsed and overlay.elapsed>=resultEnd then
        sessionSave()
        showTurn(true)
        return
      end
    elseif overlay.type=='siege' then
      local index=math.floor(overlay.elapsed/SIEGE_BEAT)+1
      local volley=overlay.siege.volleys[index]
      if volley then
        local start=(index-1)*SIEGE_BEAT
        crossedCue(before,overlay.elapsed,start+.035,'dice-roll')
        crossedCue(before,overlay.elapsed,start+1.08,'land')
        if volley.hit>0 then
          crossedCue(before,overlay.elapsed,start+1.66,'boulder-launch')
          crossedCue(before,overlay.elapsed,start+2,'fortress')
        else crossedCue(before,overlay.elapsed,start+1.30,'roll-tie') end
      end
      if overlay.elapsed>=#overlay.siege.volleys*SIEGE_BEAT then overlay=nil end
    elseif overlay.type=='resurrection' then
      crossedCue(before,overlay.elapsed,.60,'heal')
      if overlay.elapsed>=1.82 then showTurn() end
    elseif overlay.type=='attackNotice' then
      if overlay.elapsed>=attackNoticeDuration(overlay) then overlay.type,overlay.elapsed='battle',0 end
    elseif overlay.type=='trap' or overlay.type=='potion' or overlay.type=='crate' then
      local delay=overlay.type=='crate' and .9 or 0
      if delay>0 then
        local crate=overlay.event.crate
        crossedCue(before,overlay.elapsed,delay,(crate.destroyed or crate.contents=='bomb') and 'collapse' or 'heal')
      end
      if overlay.elapsed>=timers.variantUI.trapDuration+delay then
        if overlay.event.siege then overlay={type='siege',siege=overlay.event.siege,elapsed=0}
        else showTurn() end
      end
    elseif overlay.type=='turnNotice' then
      if overlay.elapsed>=TURN_NOTICE_TIME then overlay=nil end
    elseif overlay.type=='battle' then
      if overlay.event.deathMatch then playDuelCues(overlay,before)
      else playBattleCues(overlay,before) end
      if overlay.bonusElapsed then
        local beforeBonus=overlay.bonusElapsed
        overlay.bonusElapsed=beforeBonus+dt
        playRewardCues(beforeBonus,overlay.bonusElapsed)
        if beforeBonus<BONUS_TIME and overlay.bonusElapsed>=BONUS_TIME
          and mode~='online' and playerControlsReward(overlay.event.actor) then
          sessionSave(REWARD_SHOWN)
        end
      elseif mode~='online' and overlay.event.heal and not playerControlsReward(overlay.event.actor)
          and overlay.elapsed>=battleLead(overlay)+RESULT+AUTO_REWARD then
        overlay.bonusElapsed=0
      end
    end
  elseif state and state.winner~=nil then
    local before=finishElapsed
    local speed=state.finish=='siege' and CINEMATIC_SPEED or 1
    finishElapsed=math.min(FINALE_LENGTH,finishElapsed+dt*speed)
    if state.winner~=0 then
      crossedCue(before,finishElapsed,COLLAPSE_TIME,'collapse')
      local lost=timers.localDefeat(state.winner)
      crossedCue(before,finishElapsed,1.45,lost and 'defeat' or 'victory')
      if not lost then
        for burst=0,3 do crossedCue(before,finishElapsed,1.93+burst*.35,'firework') end
      end
    end
  end
  if state and state.winner==nil and not overlay and not moving and not pending then
    if mode=='solo' and state.turn==2 then
      timers.cpu=timers.cpu+dt
      if timers.cpu>1.1 then timers.cpu=0;computerAction() end
    elseif mode=='online' and onlineAllowed and onlineReady and state.turn==onlineSide
      and rules.mustPass(state) then
      -- Zompa online turns alternate strictly: a side with no legal action submits a pass.
      sendOnline({type='pass'})
    elseif mode=='local' and rules.mustPass(state) then
      localAction({type='pass'})
    elseif mode=='solo' and state.turn==1 and rules.mustPass(state) then
      localAction({type='pass'})
    end
  end
end
local function drawStageSky()
  local g=love.graphics
  local w,h=layout.w,layout.h
  local now=animationTime
  for i=1,58 do
    local x=w*((i*117%307)/307)
    local y=h*((i*173%313)/313)
    local brightness=.29+.14*math.sin(now*(.6+i%4*.13)+i*2.5)
    g.setColor(.77,.80,1,brightness)
    g.circle('fill',x,y,i%9==0 and 1.45 or .80)
  end
  for side=1,2 do
    local tint=side==1 and {.51,.17,.34} or {.17,.37,.63}
    local base=h*(side==1 and .77 or .24)
    for layer=8,1,-1 do
      local points={}
      for i=0,22 do
        local t=i/22
        points[#points+1]=w*(t*1.30-.15)
        points[#points+1]=base+math.sin(t*4.1+side*1.8+now*.30)*h*.065
          +math.sin(t*7.3+now*.14)*h*.026
      end
      g.setColor(tint[1],tint[2],tint[3],.019+layer*.002)
      g.setLineWidth(math.max(1,h*.012*layer))
      g.line((table.unpack or unpack)(points))
    end
  end
end

function timers.drawResurrectionChoice(view)
  local g=love.graphics
  local w,h=layout.w,layout.h
  local side=view.event.actor
  local width=math.min(w-16,430)
  local height=math.min(h-10,339)
  local x,y=(w-width)*.5,timers.variantUI.boardDialogTop(layout,height)
  local opening=smoothstep(view.elapsed/.24)
  g.setColor(.019,.025,.042,.59);g.rectangle('fill',0,0,w,layout.viewportH)
  panel(x,y,width,height)
  local head=height*.10
  combatTitle('Soldier Resurrection',w*.5,y+head*.46,width-16,palette.gold,1,fonts.medium)
  combatTitle(teamNames[side]..' Soldier reached enemy lines',w*.5,y+height*.16,
    width-16,teamLabels[side],1,fonts.small)
  combatTitle('Choose a warrior at full Health',w*.5,y+height*.24,
    width-16,palette.text,1,fonts.cardHint)
  local gap=6
  local bw=(width-28-gap)*.5
  local bh=height*.145
  local firstY=y+height*.34
  view.choices={}
  for i,kind in ipairs(rules.resurrectionClasses) do
    local bx=x+14+(i-1)%2*(bw+gap)
    local by=firstY+math.floor((i-1)/2)*(bh+gap)
    view.choices[i]={x=bx,y=by,w=bw,h=bh}
    g.setColor(.116,.131,.173,1);g.rectangle('fill',bx,by,bw,bh,7,7)
    frame(bx,by,bw,bh,.74,7)
    local badge=unitArt[side][kind]
    local rad=math.min(bh*.36,bw*.19)
    if badge then drawBadgeSprite(badge,bx+rad+7,by+bh*.5,rad/BADGE_R,.72+.28*opening) end
    local left=bx+rad*2+11
    text(rules.classes[kind].name,left,by+(bh-fontHeight(fonts.small))*.5,bx+bw-left-3,'left',fonts.small)
  end
  local bx=x+14+bw+gap
  local by=firstY+2*(bh+gap)
  view.choices[#rules.resurrectionClasses+1]={x=bx,y=by,w=bw,h=bh}
  g.setColor(.087,.097,.128,1);g.rectangle('fill',bx,by,bw,bh,7,7)
  frame(bx,by,bw,bh,.48,7)
  combatTitle('Keep Soldier',bx+bw*.5,by+(bh-fontHeight(fonts.small))*.5,
    bw-6,{.77,.79,.83},1,fonts.small)
  if pending or turnSendFailed then
    text(pending and 'Sending choice…' or 'Could not send. Tap to retry.',x+8,y+height-21,width-16,'center',fonts.cardHint)
  end
end

function timers.drawResurrectionResult(view)
  local event=view.event
  local side=event.actor
  local w,h=layout.w,layout.h
  local appear=smoothstep((view.elapsed-.54)/.25)
  if appear<=0 then return end
  local width=math.min(w-20,330)
  local height=math.min(70,h*.17)
  local x,y=(w-width)*.5,h*.47-height*.5
  panel(x,y,width,height)
  combatTitle(teamNames[side]..' '..rules.classes[event.resurrection.class].name..' rises',
    w*.5,y+height*.13,width-12,teamLabels[side],1,fonts.medium,appear)
  combatTitle('Full Health',w*.5,y+height*.57,width-12,palette.gold,1,fonts.small,appear)
end

function love.draw()
  if not state then return end
  -- A quiet stone-toned stage avoids a separate black rectangle around the board.
  -- Zompa's dark-purple play-area tone is the only backdrop color.
  love.graphics.setColor(.085,.066,.115,1)
  love.graphics.rectangle('fill',0,0,layout.viewportW,layout.viewportH)
  if layout.stageX>0 then love.graphics.push();love.graphics.translate(layout.stageX,0) end
  if timers.settings.open then
    drawStageSky()
    timers.settings.hits=timers.variantUI.drawSetup(love.graphics,layout,fonts,timers.settings,frame,timers.drawSetupPreview)
    if layout.stageX>0 then love.graphics.pop() end
    return
  end
  if intro and not intro.help and not blocked and introTime<introDuration then
    local mix=smoothstep((introTime-3)/(introDuration-3))
    if tileCanvas==nil then prepareTileCanvas() end
    -- Prepare the destination before the first blended frame. Online identity
    -- arrives with the initial host poll, so allow that poll to run first.
    if (mode~='online' or onlineSide) and tileCanvas and intro.surface==nil and love.graphics.origin then
      local g=love.graphics
      local scale=math.min(1,480/layout.w,900/layout.viewportH)
      local ok,surface=pcall(g.newCanvas,math.ceil(layout.w*scale),math.ceil(layout.viewportH*scale),{dpiscale=1})
      intro.surface=ok and surface and pcall(g.setCanvas,{surface,stencil=true}) and surface or false
      if intro.surface then
        g.push();g.origin();g.scale(scale,scale)
        g.clear(.085,.066,.115,1)
        drawStageSky()
        drawBoard()
        drawIntroduction()
        g.pop()
        g.setCanvas()
        intro.surfaceScale=scale
      end
    end
    if mix==0 or intro.surface then
      drawIntroduction(true)
      if mix>0 then
        love.graphics.setColor(1,1,1,mix)
        love.graphics.draw(intro.surface,0,0,0,1/intro.surfaceScale,1/intro.surfaceScale)
      end
      if layout.stageX>0 then love.graphics.pop() end
      return
    end
  end
  drawStageSky()
  local practice=intro and intro.help
  local dx,dy=moveFx.shake(moving,layout.radius)
  local shake=(dx~=0 or dy~=0) and love.graphics.push and love.graphics.translate
  if shake then love.graphics.push();love.graphics.translate(dx,dy) end
  drawBoard(practice and practice.board,practice and practice.animation)
  if shake then love.graphics.pop() end
  local waitingForRoll=mode=='online' and not onlineReady and not blocked
  if not intro and not waitingForRoll and not (overlay and (overlay.type=='opening' or overlay.type=='trap' or overlay.type=='potion' or overlay.type=='brief' or overlay.type=='crate')) then
    drawActionBar()
    drawCard()
  end
  if blocked then
    text('Online sync error: '..blocked,8,layout.h*.43,layout.w-16,'center',fonts.medium)
  end
  if practice and not blocked then drawPractice(practice)
  elseif intro and not blocked then
    drawIntroduction()
    if introTime<introDuration then
      drawIntroduction(true,1-smoothstep((introTime-3)/(introDuration-3)))
    end
  elseif overlay and overlay.type=='battle' then
    if overlay.event.deathMatch then drawDeathMatch(overlay) else drawBattleOverlay(overlay) end
  elseif overlay and overlay.type=='brief' then
    overlay.button,overlay.backButton=timers.variantUI.matchBrief(love.graphics,layout,fonts,state.options,frame)
  elseif overlay and overlay.type=='opening' then drawOpening(overlay)
  elseif waitingForRoll then drawOpening(onlineOpeningPrompt)
  elseif overlay and overlay.type=='resurrectionChoice' then timers.drawResurrectionChoice(overlay)
  elseif overlay and overlay.type=='resurrection' then timers.drawResurrectionResult(overlay)
  elseif overlay and overlay.type=='siege' then drawFinalSiege()
  elseif overlay and (overlay.type=='trap' or overlay.type=='potion' or overlay.type=='crate') then
    local event=overlay.event
    local x,y=center(event.to.r,event.to.c)
    local potion,crate=event.potion,event.crate
    local elapsed=overlay.elapsed
    if crate then
      if elapsed>=.20 and elapsed<.9 then
        local g,r=love.graphics,layout.hexR
        local arrive=smoothstep((elapsed-.20)/.16)
        local opacity=arrive*smoothstep((.9-elapsed)/.10)
        local hex=faceHex(x,y,r*.95)
        g.setColor(.025,.025,.035,.80*opacity);g.polygon('fill',hex)
        g.setColor(.84,.66,.37,.34*opacity)
        g.setLineWidth(math.max(1,r*.032));g.polygon('line',hex)
        local scale=.84+.16*arrive
        if crate.contents=='bomb' then
          -- Feather the gold backlight inside the hex to separate the dark bomb from its backing.
          for layer=12,1,-1 do
            g.setColor(1,.72,.29,.045*opacity)
            g.circle('fill',x,y+r*.06,r*(.22+layer*.042)*scale)
          end
          timers.variantUI.bomb(g,x-r*.035,y+r*.025,r*.82*scale,opacity)
        else
          timers.variantUI.potion(g,x,y-r*.075,r*1.03*scale,opacity)
        end
      end
      elapsed=elapsed-.9
      if elapsed>=0 then
        if crate.destroyed or crate.contents=='bomb' then
          timers.variantUI.trapBlast(love.graphics,x,y,layout.hexR,elapsed)
        else timers.variantUI.potionEffect(love.graphics,x,y,layout.hexR,elapsed,true) end
      end
    elseif potion then timers.variantUI.potionEffect(love.graphics,x,y,layout.hexR,elapsed,potion.gained)
    else timers.variantUI.trapBlast(love.graphics,x,y,layout.hexR,elapsed) end
    local alpha=timers.variantUI.trapCardOpacity(elapsed)
    if alpha>0 then
      local g,w,h=love.graphics,layout.w,layout.h
      local destroyed=crate and crate.destroyed
      local boxW=w*.90
      local boxH=destroyed and math.min(204,h*.54) or math.min(144,h*.39)
      local boxX,boxY=(w-boxW)*.5,timers.variantUI.boardDialogTop(layout,boxH)
      g.setColor(.016,.018,.027,.22*alpha);g.rectangle('fill',0,0,w,h)
      g.setColor(.047,.057,.077,.96*alpha);g.rectangle('fill',boxX,boxY,boxW,boxH,10,10)
      frame(boxX,boxY,boxW,boxH,.87*alpha,10)
      local label=teamNames[event.actor]..' '..rules.classes[(crate or potion or event.trap).class].name
      if destroyed then
        local isPotion=crate.contents=='potion'
        local icon=isPotion and timers.variantUI.potion or timers.variantUI.bomb
        local cx,cy=w*.5,boxY+boxH*.40
        local radius=boxH*.213
        combatTitle('Mystery Crate Destroyed',cx,boxY+boxH*.085,boxW-18,palette.gold,1,fonts.medium,alpha)
        g.setColor(.24,.16,.10,.55*alpha);g.circle('fill',cx,cy,radius*.89)
        icon(g,cx,cy,radius,alpha)
        combatTitle(isPotion and 'Health Potion Destroyed' or 'Bomb Detonated',cx,boxY+boxH*.65,
          boxW-18,palette.text,1,fonts.medium,alpha)
        combatTitle('By '..label,cx,boxY+boxH*.83,boxW-18,teamLabels[event.actor],1,fonts.small,alpha)
      else
        local title='Booby Trap Triggered'
        local result
        local fallen=crate and crate.contents=='bomb' and crate.remaining==0
          or event.trap and event.trap.remaining==0
        if crate then
          if crate.contents=='bomb' then
            title='Bomb Triggered'
            result=(-crate.change)..' Damage'
          else
            title='Health Potion Found'
            result=crate.change>0 and ('+'..crate.change..' Health') or 'Already at full Health'
          end
        elseif potion then
          title=potion.gained and 'Health Potion Collected' or 'Health Potion Destroyed'
          result=potion.gained and ('+'..potion.gained..' Health') or nil
          if not potion.gained then label='By '..label end
        else
          result=event.trap.damage..' Damage'..(event.trap.remaining==0 and '  ·  Defeated' or '')
        end
        combatTitle(title,w*.5,boxY+boxH*(result and .12 or .20),boxW-18,palette.gold,1,fonts.medium,alpha)
        combatTitle(label,w*.5,boxY+boxH*(result and .37 or .53),boxW-18,teamLabels[event.actor],1,fonts.large,alpha)
        if fallen and result then
          result=result..' · Defeated'
          local font=fonts.medium
          local fontH=fontHeight(font)
          local size=math.min(12,fontH*.43)
          local reserved=size*2+6
          local available=boxW-20-reserved
          local measured=font.getWidth and font:getWidth(result) or #result*fontH*.52
          local fit=math.min(1,(available-8)/math.max(1,measured))
          local textY=boxY+boxH*.73
          duelSkull(g,w*.5-(measured*fit+reserved)*.5+size,
            textY+fontH*fit*.5,size,alpha,animationTime)
          combatTitle(result,w*.5+reserved*.5,textY,available,palette.text,fit,font,alpha)
        elseif result then
          combatTitle(result,w*.5,boxY+boxH*.73,boxW-18,palette.text,1,fonts.medium,alpha)
        end
      end
    end
  elseif overlay then drawBoardNotice()
  elseif state.winner~=nil then drawFinished() end
  if detail.piece and not (practice and practice.expanded) then
    if overlay or moving or blocked or state.winner or intro or not cardBox or cardBox.piece~=detail.piece then
      detail.piece=nil
    else
      local piece=detail.piece
      local sprite=piece.class=='fortress' and siegeKeeps[piece.owner] or fighterArt[piece.owner][piece.class]
      detail.draw(layout,sprite,rules.classes[piece.class],rules.attackRange(piece.class),animationTime-detail.started)
    end
  end
  if layout.stageX>0 then love.graphics.pop() end
end
function love.mousepressed(x,y,button) if button==1 then touch(x,y) end end
function love.touchpressed(_,x,y) touch(x,y) end
function love.keypressed(key)
  if key=='escape' then
    if timers.settings.open then
      if timers.settings.dropdown then timers.settings.dropdown=false;timers.settings.hits=nil
      else timers.settings.open,timers.settings.review=false,nil end
      return
    end
    if detail.piece then
      detail.piece=nil
      if intro and intro.help and intro.help.expanded then
        intro.help.expanded=nil
        intro.help.step='complete'
      end
      return
    end
    if intro and intro.help then
      closePractice()
      return
    end
    selected,inspected,targets,intended=nil,nil,{},nil
    actionBox,cancelBox,cardBox=nil,nil,nil
    turnSendFailed=false
  end
end
