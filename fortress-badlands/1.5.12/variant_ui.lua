local ui={}

local ivory={.95,.90,.82}
local muted={.67,.66,.66}
local gold={.84,.69,.43}

local function paint(g,tint,alpha)
  g.setColor(tint[1],tint[2],tint[3],alpha or 1)
end

local boards=require('boards')

local function drawSetup(g,layout,fonts,setup,frame,preview)
  local options=setup.options
  local w=math.min(layout.w-14,420)
  local h=math.min(layout.h-12,setup.advanced and 650 or 510)
  local x,y=(layout.w-w)*.5,(layout.h-h)*.5
  local pad=math.min(14,w*.05)
  local left,right=x+pad,x+w-pad
  local span=right-left
  local compact=h<390
  local titleY=y+9
  local pickerY=y+(compact and 34 or 44)
  local pickerH=compact and 32 or 40
  local footerH=compact and 32 or 42
  local footerY=y+h-footerH-9
  local rowH=math.min(36,math.max(19,math.floor((h-175)/9)))
  if h<320 then rowH=math.max(12,math.min(24,math.floor((h-165)/8))) end
  local sectionsH=setup.advanced and (8*rowH+16) or 0
  local advanceH=compact and 28 or 35
  local advanceY=footerY-sectionsH-advanceH-10
  local previewY=pickerY+pickerH+7
  local previewH=advanceY-previewY-6
  local hit={}
  local function rect(b,tint,alpha)
    paint(g,tint,alpha);g.rectangle('fill',b.x,b.y,b.w,b.h,7,7)
  end
  local function drawText(label,box,font,tint,align)
    local fh=font.getHeight and font:getHeight() or font.size or 14
    g.setFont(font);paint(g,tint)
    g.printf(label,box.x,box.y+math.max(0,(box.h-fh)*.5),box.w,align or 'left')
  end
  local function control(key,box,tint,enabled)
    if setup.review and key~='continue' and key~='advanced' then enabled=false end
    rect(box,tint)
    frame(box.x,box.y,box.w,box.h,enabled and .77 or .27,7)
    if key and enabled then hit[key]=box end
  end
  local function button(key,label,box,tint,enabled)
    control(key,box,tint,enabled)
    drawText(label,box,fonts.small,enabled and ivory or muted,'center')
  end
  local function switch(box,checked,enabled)
    rect(box,checked and {.16,.38,.27} or {.18,.20,.25})
    frame(box.x,box.y,box.w,box.h,enabled and .72 or .33,8)
    paint(g,checked and {.85,.98,.88} or muted)
    g.circle('fill',box.x+box.w*(checked and .72 or .28),box.y+box.h*.5,box.h*.29)
  end
  local labelFont=fonts.cardHint or fonts.small
  local function row(key,label,ry,kind,enabled,low,high)
    enabled=enabled and not setup.review
    local box={x=left+5,y=ry,w=span-10,h=rowH-1}
    local tint=enabled and ivory or muted
    if kind=='step' then
      local bw=math.max(25,math.min(38,span*.115))
      local bx=right-6-bw
      drawText(label,{x=left+9,y=ry,w=span-3*bw-22,h=rowH},labelFont,tint)
      drawText(tostring(options[key]),{x=bx-bw,y=ry,w=bw,h=rowH},labelFont,enabled and gold or muted,'center')
      for _,delta in ipairs({-1,1}) do
        local allowed=enabled and options[key]+delta>=low and options[key]+delta<=high
        button(key..delta,delta==1 and '+' or '−',{x=bx+(delta==1 and 0 or -2*bw),y=ry+1,w=bw,h=rowH-3},
          allowed and {.23,.17,.105} or {.13,.14,.18},allowed)
      end
    else
      drawText(label,{x=left+9,y=ry,w=span-62,h=rowH},labelFont,tint)
      local bh=math.min(22,rowH-3)
      switch({x=right-47,y=ry+(rowH-bh)*.5,w=39,h=bh},options[key],enabled)
      if enabled then hit[key]=box end
    end
  end
  g.setColor(.025,.02,.034,.85);g.rectangle('fill',0,0,layout.w,layout.viewportH)
  rect({x=x,y=y,w=w,h=h},{.06,.075,.106})
  frame(x,y,w,h,1,11)
  drawText('Match Setup',{x=left,y=titleY,w=span,h=26},fonts.medium,gold,'center')
  local picker={x=left,y=pickerY,w=span,h=pickerH}
  control('picker',picker,{.125,.132,.165},true)
  drawText(boards[options.board].name,{x=left+11,y=pickerY,w=span-36,h=pickerH},fonts.small,ivory)
  paint(g,gold);g.setLineWidth(1.7)
  local cx,cy=right-16,pickerY+pickerH*.5
  local arrow=setup.dropdown and -3 or 3
  g.line(cx-5,cy-arrow,cx,cy+arrow,cx+5,cy-arrow)
  if previewH>=46 then
    rect({x=left,y=previewY,w=span,h=previewH},{.041,.045,.065})
    local noteH=not setup.advanced and 37 or 0
    preview(left+7,previewY+5,span-14,previewH-noteH-8)
    if noteH>0 then
      drawText(boards[options.board].description,{x=left+7,y=previewY+previewH-noteH+3,w=span-14,h=21},
        labelFont,muted,'center')
    end
  end
  local advanced={x=left,y=advanceY,w=span,h=advanceH}
  control('advanced',advanced,{.104,.112,.143},true)
  drawText('Advanced Options',{x=left+9,y=advanceY,w=span-54,h=advanceH},fonts.small,ivory)
  switch({x=right-47,y=advanceY+(advanceH-21)*.5,w=39,h=21},setup.advanced,true)
  if setup.advanced then
    local ry=advanceY+advanceH+4
    rect({x=left,y=ry,w=span,h=rowH*3},{.088,.10,.133})
    row('crates','Mystery Crates',ry,'switch',true)
    row('crateCount','Crate Count',ry+rowH,'step',options.crates,1,6)
    row('destroyCrates','Destructible Crates',ry+2*rowH,'switch',options.crates)
    ry=ry+3*rowH+4
    rect({x=left,y=ry,w=span,h=rowH*4},{.088,.10,.133})
    row('wall','Border Wall',ry,'switch',true)
    row('wallHealth','Section Health',ry+rowH,'step',options.wall,1,50)
    row('wallShield','Section Shield',ry+2*rowH,'step',options.wall,0,11)
    row('overWall','Ranged Fire Over Wall',ry+3*rowH,'switch',options.wall)
    ry=ry+4*rowH+4
    rect({x=left,y=ry,w=span,h=rowH},{.088,.10,.133})
    row('resurrection','Soldier Resurrection',ry,'switch',true)
  end
  local bw=(span-9)*.5
  if not setup.review then button('back','Back',{x=left,y=footerY,w=bw,h=footerH},{.20,.21,.25},true) end
  button('continue','Continue',{x=right-bw,y=footerY,w=bw,h=footerH},{.36,.235,.115},true)
  if setup.error then
    drawText(setup.error,{x=left,y=y+h+1,w=span,h=16},labelFont,{1,.60,.54},'center')
  end
  if setup.dropdown then
    hit={picker=picker}
    local optionH=math.min(36,math.floor((y+h-9-pickerY-pickerH-3)/#boards))
    for i,board in ipairs(boards) do
      local box={x=left,y=pickerY+pickerH+3+(i-1)*optionH,w=span,h=optionH}
      control(board.id,box,options.board==board.id and {.28,.21,.13} or {.105,.119,.16},true)
      drawText(board.name,{x=left+11,y=box.y,w=span-23,h=box.h},fonts.small,
        options.board==board.id and gold or ivory)
    end
  end
  return hit
end

function ui.drawSetup(g,layout,fonts,setup,frame,preview)
  -- Keep the dropdown and controls distinct in very short hosted windows.
  local scale=math.min(1,layout.w/212,layout.h/276)
  if scale==1 then return drawSetup(g,layout,fonts,setup,frame,preview) end
  local virtual={w=layout.w/scale,h=layout.h/scale,viewportH=layout.viewportH/scale}
  g.push()
  g.scale(scale)
  local hits=drawSetup(g,virtual,fonts,setup,frame,preview)
  g.pop()
  for _,b in pairs(hits) do
    b.x,b.y,b.w,b.h=b.x*scale,b.y*scale,b.w*scale,b.h*scale
  end
  return hits
end

function ui.tapSetup(setup,x,y)
  for key,b in pairs(setup.hits or {}) do
    if x>=b.x and y>=b.y and x<b.x+b.w and y<b.y+b.h then
      if key=='back' or key=='continue' then return key end
      if key=='picker' then setup.dropdown=not setup.dropdown
      elseif key=='advanced' then setup.advanced=not setup.advanced
      elseif boards[key] then
        if setup.options.board~=key then
          setup.options.board=key
          setup.options.crateCount=boards[key].crateCount
        end
        setup.dropdown=false
      else
        local field,delta=key:match('^(%a+)(%-?1)$')
        if delta then setup.options[field]=setup.options[field]+tonumber(delta)
        else setup.options[key]=not setup.options[key] end
      end
      setup.hits=nil
      return
    end
  end
  if setup.dropdown then setup.dropdown=false;setup.hits=nil end
end

local limestone={
  top={.655,.566,.443}, face={.368,.304,.224}, rear={.367,.306,.230},
  edge={.84,.76,.61}, shadow={.085,.069,.055},
  rubble={.29,.235,.166}, rubbleTop={.62,.524,.395},
}
function ui.wall(g,x,y,r,hp,maximum,alpha)
  alpha=alpha or 1
  local l,rr=x-r*.815,x+r*.815
  local bevel=r*.079
  local rear,rearJoin=y-r*.235,y-r*.075
  local frontJoin,foot=y+r*.068,y+r*.198
  local function tint(color,strength)
    paint(g,limestone[color],(strength or 1)*alpha)
  end
  local function chip(cx,cy,size)
    tint('shadow',.78);g.circle('fill',cx+1,cy+1,size)
    tint('rubble');g.polygon('fill',cx-size,cy,cx-size*.3,cy-size,cx+size,cy-size*.2,cx+size*.36,cy+size)
    tint('rubbleTop');g.line(cx-size,cy,cx-size*.3,cy-size,cx+size,cy-size*.2)
  end
  if hp<=0 then
    g.setLineWidth(1)
    for i=1,4 do
      chip(x+r*((i*7)%13-6)*.095,y+r*((i*5)%9-4)*.045,r*(.045+i%3*.022))
    end
    return
  end
  -- Cast shadow falls away from the darker far face onto the board.
  for i=1,8 do
    local spread=i/8
    local tail=rear-r*.18*spread
    tint('shadow',.68*(1-spread*.84)*.26)
    g.polygon('fill',l+bevel*(.61+.31*spread),tail,rr-bevel*(.58+.15*spread),tail,rr+r*.012,rearJoin,l,rearJoin)
  end
  tint('shadow',.41)
  g.polygon('fill',l,rearJoin,rr,rearJoin,rr,foot+r*.042,rr-bevel*.6,foot+r*.084,
    l+bevel*.6,foot+r*.084,l,foot+r*.042)
  tint('rear')
  g.polygon('fill',l,rearJoin,l+bevel,rear,rr-bevel,rear,rr,rearJoin)
  tint('top')
  g.polygon('fill',l,rearJoin,rr,rearJoin,rr,frontJoin,l,frontJoin)
  tint('face')
  g.polygon('fill',l,frontJoin,rr,frontJoin,rr,foot-bevel*.31,rr-bevel,foot,l+bevel,foot,l,foot-bevel*.31)
  g.setLineWidth(math.max(.86,r*.026))
  tint('shadow',.82);g.line(l+bevel,rear+.18,rr-bevel,rear+.18)
  tint('edge',.71);g.line(l+1,rearJoin,rr-1,rearJoin)
  paint(g,{.89,.80,.65},.60*alpha);g.line(l+1,frontJoin,rr-1,frontJoin)
  tint('shadow',.70);g.line(l+bevel,foot-.8,rr-bevel,foot-.8)
  local edges={rear,rearJoin,frontJoin,foot}
  for i=1,26 do
    local sx=l+bevel+(rr-l-2*bevel)*((i*43+math.floor(x)*11)%91)/91
    local band=i%3+1
    local sy=edges[band]+(edges[band+1]-edges[band])*(.19+(i*13%17)/32)
    local light=i%4==0
    if light then paint(g,{.88,.78,.60},.25*alpha) else tint('shadow',.27) end
    g.line(sx,sy,math.min(rr-.8,sx+r*(.025+i%3*.012)),sy-r*.006)
  end
  if hp<maximum then
    local health=hp/maximum
    tint('shadow',.92);g.setLineWidth(math.max(1.1,r*.05))
    g.line(x+r*.17,rear,x+r*.09,rearJoin,x+r*.15,frontJoin,x+r*.07,foot)
    if health<=.60 then
      g.line(x-r*.37,rear,x-r*.45,rearJoin,x-r*.31,frontJoin,x-r*.39,foot)
      g.line(x+r*.09,rearJoin,x+r*.31,rearJoin+r*.044,x+r*.43,rear)
    end
    if health<=.25 then
      g.line(x+r*.57,rear,x+r*.48,frontJoin,x+r*.58,foot)
      g.polygon('fill',rr-r*.19,foot,rr-r*.12,frontJoin,rr,frontJoin,rr,foot-r*.06)
      g.setLineWidth(1)
      chip(rr-r*.16,foot+r*.10,r*.075)
      chip(l+r*.24,foot+r*.075,r*.060)
    end
  end
end

-- The ring runs clockwise. Adjacent sections share the same cross-section at
-- each hex boundary, and the offset stone bands meet at a true miter at the bend.
function ui.ringWall(g,ax,ay,x,y,bx,by,r,hp,maximum,previousIntact,nextIntact)
  local function normal(dx,dy)
    local length=math.sqrt(dx*dx+dy*dy)
    return -dy/length,dx/length
  end
  local ux,uy=normal(x-ax,y-ay)
  local vx,vy=normal(bx-x,by-y)
  local joint=1+ux*vx+uy*vy
  local mx,my=(ux+vx)/joint,(uy+vy)/joint
  local ends={{ax,ay,ux,uy},{x,y,mx,my},{bx,by,vx,vy}}
  local bands={
    {-0.225,-0.122,'rear'},{-0.122,0.097,'top'},{0.097,0.218,'face'},
  }
  local function point(node,offset)
    return node[1]+node[3]*r*offset,node[2]+node[4]*r*offset
  end
  local function band(a,b,low,high,shadow)
    local lx,ly=point(a,low)
    local rx,ry=point(b,low)
    local hx,hy=point(b,high)
    local tx,ty=point(a,high)
    g.polygon('fill',lx,ly+shadow,rx,ry+shadow,hx,hy+shadow,tx,ty+shadow)
  end
  local function edge(a,b,offset)
    local xx,yy=point(a,offset)
    local nx,ny=point(b,offset)
    g.line(xx,yy,nx,ny)
  end
  local function across(a,b,t)
    local px=a[1]+(b[1]-a[1])*t
    local py=a[2]+(b[2]-a[2])*t
    return {px,py,a[3]+(b[3]-a[3])*t,a[4]+(b[4]-a[4])*t}
  end

  paint(g,limestone.shadow,.52)
  for i=1,2 do band(ends[i],ends[i+1],-.245,.235,r*.10) end
  for i=1,2 do
    local a,b=ends[i],ends[i+1]
    for _,layer in ipairs(bands) do
      paint(g,limestone[layer[3]])
      band(a,b,layer[1],layer[2],0)
    end
    g.setLineWidth(math.max(.5,r*.022))
    paint(g,limestone.edge,.75);edge(a,b,-.119)
    paint(g,limestone.edge,.54);edge(a,b,.087)
    paint(g,limestone.shadow,.62);edge(a,b,.205)

    -- Stagger the masonry across the two faces. Miter seams remain readable
    -- through the edge highlights without clear gaps in the stonework.
    g.setLineWidth(math.max(.5,r*.015))
    for j=1,7 do
      local along=(j-.5)/7
      local node=across(a,b,along)
      local offset=j%2==0 and -.065 or .017
      local ox,oy=point(node,offset)
      paint(g,j%3==0 and limestone.edge or limestone.shadow,.32)
      g.line(ox,oy,ox+(b[1]-a[1])*.08,oy+(b[2]-a[2])*.08)
    end
  end

  g.setLineWidth(math.max(.5,r*.026))
  paint(g,limestone.shadow,.63)
  for i,intact in ipairs({previousIntact,nextIntact}) do
    local endpoint=ends[i==1 and 1 or 3]
    local sx,sy=point(endpoint,-.216)
    local ex,ey=point(endpoint,.205)
    if intact then
      g.line(sx,sy,ex,ey)
    else
      local mx2,my2=point(endpoint,-.012)
      g.line(sx,sy,mx2+(x-endpoint[1])*.06,my2+(y-endpoint[2])*.06,ex,ey)
    end
  end

  local health=hp/maximum
  local cracks=health<=.25 and 3 or health<=.60 and 2 or hp<maximum and 1 or 0
  g.setLineWidth(math.max(.6,r*.045))
  paint(g,limestone.shadow,.92)
  for i=1,cracks do
    local a,b=ends[i%2+1],ends[i%2+2]
    local t=.29+i*.13
    local sx,sy=point(across(a,b,t),-.215)
    local kx,ky=point(across(a,b,t+.10),-.066)
    local zx,zy=point(across(a,b,t-.045),.076)
    local ex,ey=point(across(a,b,t+.075),.208)
    g.line(sx,sy,kx,ky,zx,zy,ex,ey)
  end
end

ui.trapDuration=3.75
function ui.trapCardOpacity(elapsed)
  local function ease(t)
    t=math.max(0,math.min(1,t))
    return t*t*(3-2*t)
  end
  return ease((elapsed-.38)/.26)*ease((ui.trapDuration-elapsed)/.50)
end

function ui.trapBlast(g,x,y,r,elapsed)
  local t=math.min(1,elapsed/.96)
  if t>=1 then return end
  local fade=1-t
  g.setColor(1,.28,.08,.42*fade^2)
  g.circle('fill',x,y,r*(1+1.85*t))
  g.setColor(1,.83,.43,.84*fade^3)
  g.circle('fill',x,y,r*(.43+.71*t))
  g.setColor(1,.60,.25,.92*fade);g.setLineWidth(math.max(2,r*.14))
  g.circle('line',x,y,r*(.55+2.65*t))
  for i=1,22 do
    local angle=i*2.39996
    local dx,dy=math.cos(angle),math.sin(angle)
    local reach=r*(.47+t*(1.8+i%5*.32))
    local px,py=x+dx*reach,y+dy*reach-r*t*.46
    g.setColor(1,.43+i%4*.14,.19,.97*fade)
    g.line(px,py,px+dx*r*(.24+i%3*.13),py+dy*r*(.24+i%3*.13))
  end
end

function ui.potion(g,x,y,r,alpha)
  local unit=r*.52
  local function tint(red,green,blue,opacity)
    g.setColor(red,green,blue,(opacity or 1)*(alpha or 1))
  end
  tint(.071,.028,.041,.62);g.circle('fill',x+unit*.09,y+unit*.23,unit)
  tint(.20,.075,.101)
  g.rectangle('fill',x-unit*.81,y-unit*.39,unit*1.62,unit*1.43,unit*.45,unit*.45)
  tint(.77,.13,.22);g.rectangle('fill',x-unit*.66,y-unit*.26,unit*1.32,unit*1.15,unit*.37,unit*.37)
  tint(.94,.27,.31);g.circle('fill',x-unit*.07,y+unit*.22,unit*.49)
  tint(.97,.69,.57);g.setLineWidth(math.max(1,unit*.12))
  g.rectangle('line',x-unit*.65,y-unit*.26,unit*1.30,unit*1.14,unit*.35,unit*.35)
  tint(.89,.65,.46);g.rectangle('fill',x-unit*.39,y-unit*.71,unit*.78,unit*.40,unit*.10,unit*.10)
  tint(1,.92,.76)
  g.rectangle('fill',x-unit*.36,y+unit*.19,unit*.72,unit*.17)
  g.rectangle('fill',x-unit*.085,y-unit*.075,unit*.17,unit*.70)
end

local crateArt
function ui.loadArt(g)
  local ok,image=pcall(g.newImage,'art/mystery-crate.png')
  if ok and image and g.draw then
    if image.setFilter then image:setFilter('linear','linear') end
    crateArt=image
  end
end

function ui.crate(g,x,y,r,alpha)
  local o=alpha or 1
  local radius=r*.82
  if crateArt and g.draw then
    local width,height=crateArt:getDimensions()
    local scale=2*radius/(height-4) -- The packaged sprite has two pixels of transparent padding at each tip.
    g.setColor(1,1,1,o)
    g.draw(crateArt,x,y,0,scale,scale,width/2,height/2)
    return
  end
  local w=radius*math.sqrt(3)*.5
  local hex={x,y-radius,x+w,y-radius*.5,x+w,y+radius*.5,
    x,y+radius,x-w,y+radius*.5,x-w,y-radius*.5}
  g.setColor(.43,.26,.14,o);g.polygon('fill',hex)
  g.setColor(.72,.53,.33,o);g.setLineWidth(math.max(1,r*.09))
  g.polygon('line',hex)
  g.setColor(1,.89,.64,o);g.setLineWidth(math.max(1.5,r*.11))
  g.line(x-r*.18,y-r*.20,x-r*.10,y-r*.29,x+r*.11,y-r*.29,x+r*.20,y-r*.18,
    x+r*.16,y-r*.06,x,y+r*.04,x,y+r*.14)
  g.circle('fill',x,y+r*.29,math.max(1,r*.055))
end

function ui.bomb(g,x,y,r,alpha)
  local o=alpha or 1
  g.setColor(.09,.085,.11,o);g.circle('fill',x-r*.02,y+r*.12,r*.55)
  g.setColor(.20,.19,.22,o);g.circle('fill',x-r*.09,y+r*.03,r*.43)
  g.setColor(.44,.42,.46,.7*o);g.circle('fill',x-r*.22,y-r*.09,r*.13)
  g.setColor(.33,.29,.25,o);g.rectangle('fill',x+r*.08,y-r*.49,r*.30,r*.22,2,2)
  g.setColor(.83,.64,.35,o);g.setLineWidth(math.max(1,r*.13))
  g.line(x+r*.22,y-r*.46,x+r*.32,y-r*.68,x+r*.51,y-r*.69)
  g.setColor(1,.56,.15,.48*o);g.circle('fill',x+r*.54,y-r*.70,r*.22)
  g.setColor(1,.84,.40,o);g.circle('fill',x+r*.54,y-r*.70,r*.11)
end

function ui.scorch(g,x,y,r)
  local opacity=.70
  g.setColor(.12,.078,.047,.23*opacity);g.circle('fill',x,y,r*.71)
  g.setColor(.10,.067,.048,.41*opacity);g.circle('fill',x,y,r*.52)
  g.setColor(.078,.052,.041,.55*opacity);g.circle('fill',x,y,r*.32)
  for i=1,7 do
    local angle=i*2.39996
    local reach=r*(.38+i%3*.09)
    g.circle('fill',x+math.cos(angle)*reach,y+math.sin(angle)*reach,r*.055)
  end
end

function ui.boardDialogTop(layout,height)
  local middle=layout.y+layout.boardH*.5
  return math.max(5,math.min(layout.h-height-5,middle-height*.5))
end

function ui.matchBrief(g,layout,fonts,options,frame)
  local w,h=layout.w,layout.h
  local panelW=math.min(w*.92,470)
  local left=(w-panelW)*.5
  local iconX,textX,textW=left+31,left+57,panelW-70
  local bodyFont=fonts.stat
  local function fontHeight(font)
    return font.getHeight and font:getHeight() or font.size
  end
  local function bodyHeight(label)
    if bodyFont.getWrap then
      local _,lines=bodyFont:getWrap(label,textW)
      return #lines*fontHeight(bodyFont)*bodyFont:getLineHeight()
    end
    return math.ceil(#label*fontHeight(bodyFont)*.45/textW)*fontHeight(bodyFont)
  end

  local detailOffset=8+fontHeight(fonts.small)+3
  local opens=options.destroyCrates and 'Step on one to open it, or attack to destroy it.' or 'Step on a crate to open it.'
  local contents='Each crate holds a potion or a bomb.'
  local endGaps=options.crates and options.crateCount==9 and not options.legacyCrates
  local board=boards[options.board or 'classic']
  local hasGaps=endGaps or options.legacyFlankWall
  local crossing=board.wallRing and 'Eight sections surround both Fortresses. Break a section to get inside.'
    or (board.crossings or board.bridgeLanes) and (options.legacyBridgeWall
    and 'One lane on each bridge stays open.' or 'Break a section to open a crossing.')
    or hasGaps and 'End gaps are open.' or 'Break a section to cross.'
  local ranged=options.overWall and ' Ranged fire can pass over.' or ' Wall sections block ranged fire.'
  local wallDetail=crossing..ranged
  local itemH=math.max(33,fontHeight(bodyFont)+11)
  local crateH=options.crates and (detailOffset+bodyHeight(opens)+8+bodyHeight(contents)+6+2*itemH+8) or 0
  local wallH=options.wall and (detailOffset+bodyHeight(wallDetail)+9) or 0
  local gap=options.crates and options.wall and 6 or 0
  local resurrectionDetail='Reach enemy lines to choose a full-Health warrior.'
  local resurrectionH=options.resurrection and (detailOffset+bodyHeight(resurrectionDetail)+9) or 0
  local resurrectionGap=options.resurrection and (options.wall or options.crates) and 6 or 0
  local panelH=110+crateH+wallH+gap+resurrectionH+resurrectionGap
  local scale=math.min(1,(h-10)/panelH)
  local top=ui.boardDialogTop(layout,panelH*scale)
  local offsetX,offsetY=(1-scale)*w*.5,(1-scale)*top
  local bodyTint={.80,.79,.78}
  local function text(label,x,y,width,font,tint,align)
    g.setFont(font);paint(g,tint);g.printf(label,x,y,width,align or 'left')
  end
  g.setColor(.020,.019,.027,.79);g.rectangle('fill',0,0,w,layout.viewportH)
  if scale<1 then
    g.push()
    g.translate(offsetX,offsetY)
    g.scale(scale,scale)
  end
  g.setColor(.067,.079,.104,1);g.rectangle('fill',left,top,panelW,panelH,12,12)
  frame(left,top,panelW,panelH,1,12)
  text('This Match Includes',left+8,top+14,panelW-16,fonts.medium,gold,'center')
  local ry=top+49
  local function icon(kind,cy)
    local radius=14.5
    g.setColor(.126,.133,.162,1)
    g.rectangle('fill',iconX-radius,cy-radius,2*radius,2*radius,6,6)
    g.setColor(.49,.42,.32,.37);g.setLineWidth(1)
    g.rectangle('line',iconX-radius+.5,cy-radius+.5,2*radius-1,2*radius-1,6,6)
    if kind=='bomb' then
      -- Soft amber falloff separates the dark silhouette from the icon well.
      for ring=12,1,-1 do
        local f=ring/12
        g.setColor(.99,.70,.31,.047+.123*(1-f))
        g.circle('fill',iconX,cy+1.1,14.1*f)
      end
      ui.bomb(g,iconX-.5,cy+.8,14.3)
    elseif kind=='potion' then ui.potion(g,iconX,cy-1,23.5)
    elseif kind=='crate' then ui.crate(g,iconX,cy,13.5)
    else ui.wall(g,iconX,cy,14.1,1,1) end
  end
  local function section(title,detail,height)
    g.setColor(.096,.108,.14,1);g.rectangle('fill',left+9,ry,panelW-18,height,7,7)
    text(title,textX,ry+8,textW,fonts.small,ivory)
    text(detail,textX,ry+detailOffset,textW,bodyFont,bodyTint)
  end
  if options.crates then
    local count=options.crateCount
    section(count..(count==1 and ' Mystery Crate' or ' Mystery Crates'),opens,crateH)
    icon('crate',ry+23)
    local y=ry+detailOffset+bodyHeight(opens)+8
    text(contents,textX,y,textW,bodyFont,bodyTint)
    y=y+bodyHeight(contents)+6
    local centerY=y+itemH*.5
    icon('potion',centerY)
    text('Potion  +12 Health',textX,centerY-fontHeight(bodyFont)*.5,textW,bodyFont,ivory)
    centerY=centerY+itemH
    icon('bomb',centerY)
    text('Bomb  −12 Health',textX,centerY-fontHeight(bodyFont)*.5,textW,bodyFont,ivory)
    ry=ry+crateH+gap
  end
  if options.wall then
    section('Border Wall',wallDetail,wallH)
    icon('wall',ry+23)
    ry=ry+wallH
  end
  if options.resurrection then
    ry=ry+resurrectionGap
    section('Soldier Resurrection',resurrectionDetail,resurrectionH)
    paint(g,gold)
    g.polygon('fill',iconX,ry+13,iconX+7,ry+23,iconX,ry+33,iconX-7,ry+23)
    ry=ry+resurrectionH
  end
  local gutter,margin=10,12
  local width=(panelW-2*margin-gutter)/2
  local function footer(label,x,primary)
    local box={x=x,y=ry+9,w=width,h=39}
    paint(g,primary and {.29,.19,.094} or {.105,.12,.15})
    g.rectangle('fill',box.x,box.y,box.w,box.h,7,7)
    frame(box.x,box.y,box.w,box.h,primary and 1 or .63,7)
    text(label,box.x,box.y+(box.h-fontHeight(fonts.small))*.5,box.w,fonts.small,ivory,'center')
    box.x,box.y=offsetX+box.x*scale,offsetY+box.y*scale
    box.w,box.h=box.w*scale,box.h*scale
    return box
  end
  local back=footer('Back',left+margin,false)
  local button=footer('Continue',left+margin+width+gutter,true)
  if scale<1 then g.pop() end
  return button,back
end

function ui.potionEffect(g,x,y,r,elapsed,collected)
  local t=math.min(1,elapsed/.95)
  if t>=1 then return end
  local opacity=1-t
  if not collected then
    g.setColor(1,.35,.53,.36*opacity^2)
    g.circle('fill',x,y,r*(.70+1.8*t))
    g.setColor(1,.79,.84,.77*opacity^3)
    g.circle('fill',x,y,r*(.34+.55*t))
  end
  for i=1,collected and 13 or 18 do
    local angle=i*2.39996
    local dx,dy=math.cos(angle),math.sin(angle)
    local reach=r*(.28+t*(.75+i%4*.33))
    local px,py=x+dx*reach,y+dy*reach-r*t*(collected and 1.4 or .38)
    local size=math.max(1,r*(collected and .13 or .23)*(1-t*.53))
    if collected then
      g.setColor(.55,1,.75,opacity)
      g.circle('fill',px,py,size*.76)
    else
      g.setColor(i%3==0 and 1 or .94,i%3==0 and .80 or .29,.43,opacity)
      g.polygon('fill',px+dx*size,py+dy*size,
        px-dy*size*.55,py+dx*size*.55,px-dx*size*.52,py-dy*size*.52)
    end
  end
  g.setColor(collected and .32 or 1,collected and .91 or .25,collected and .62 or .43,.63*opacity)
  g.setLineWidth(2)
  g.circle('line',x,y,r*(.52+t*1.35))
end

function ui.explosion(g,x,y,r,elapsed)
  local t=math.min(1,elapsed/.9)
  if t>=1 then return end
  g.setColor(1,.51,.15,(1-t)^2*.85)
  g.circle('fill',x,y,r*(.25+1.4*t))
  g.setColor(1,.72,.35,(1-t)*.80);g.setLineWidth(2)
  g.circle('line',x,y,r*(.35+2.2*t))
  for i=1,16 do
    local angle=i*2.39996
    local reach=r*(.4+t*(1.5+i%4*.32))
    local dx,dy=math.cos(angle),math.sin(angle)
    local px,py=x+dx*reach,y+dy*reach-r*t*.36
    g.setColor(1,.46+i%3*.17,.18,(1-t)*.9)
    g.line(px,py,px+dx*r*.32,py+dy*r*.32)
  end
end

return ui
