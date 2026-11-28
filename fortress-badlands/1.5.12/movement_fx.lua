-- Board movement presentation. All routes are already committed by the game rules.
local M={}
local profiles={
  soldier  ={travel=.43,settle=.16,lift=.20,impact=.56,tint={.91,.80,.60},sparks=5},
  archer   ={travel=.42,settle=.15,lift=.28,impact=.32,tint={.84,.78,.65},sparks=4},
  assassin ={travel=.36,settle=.16,lift=.12,impact=.23,tint={.64,.74,.85},sparks=4},
  wizard   ={travel=.63,settle=.24,lift=.27,impact=.64,tint={.77,.61,1},sparks=8},
  barbarian={travel=.49,settle=.19,lift=.24,impact=.75,tint={.90,.66,.40},sparks=7},
  ogre     ={travel=.51,settle=.29,lift=.12,impact=1,tint={.79,.65,.49},sparks=9},
}

local function smooth(t)
  t=math.max(0,math.min(1,t))
  return t*t*(3-2*t)
end

function M.new(event,class)
  local profile=profiles[class]
  local steps=#event.route-1
  local travel=profile.travel+math.max(0,steps-1)*.16
  return {event=event,id=event.id,class=class,profile=profile,elapsed=0,
    route=event.route,travel=travel,duration=travel+profile.settle}
end

function M.update(move,dt,playCue)
  local before=move.elapsed
  move.elapsed=before+dt
  if before<move.travel and move.elapsed>=move.travel then playCue('move-'..move.class) end
  return move.elapsed>=move.duration
end

local function particles(g,x,y,rad,t,look,magic)
  if t<=0 or t>=1 then return end
  local opacity=(1-t)^1.7*look.impact
  local tint=look.tint
  for i=1,look.sparks do
    local angle=i*2.39996
    local reach=rad*(.35+t*(.47+(i%4)*.12)*look.impact)
    local px=x+math.cos(angle)*reach
    local py=y+math.sin(angle)*reach*(magic and .85 or .31)-math.sin(t*math.pi)*rad*.23
    local size=rad*(.025+i%3*.017)*(1-t*.46)
    g.setColor(tint[1],tint[2],tint[3],opacity)
    if magic then
      g.polygon('fill',px,py-size*1.9,px+size,py,px,py+size*1.9,px-size,py)
    else
      g.circle('fill',px,py,math.max(.65,size))
    end
  end
  g.setColor(tint[1],tint[2],tint[3],opacity*.54)
  g.setLineWidth(math.max(1,rad*.063))
  g.circle('line',x,y,rad*(.40+t*.64))
end

function M.shake(move,rad)
  if not move or move.class~='ogre' then return 0,0 end
  local age=move.elapsed-move.travel
  if age<0 or age>=.24 then return 0,0 end
  local strength=(1-age/.24)^2*math.min(3.2,rad*.13)
  return math.sin(age*102)*strength,math.cos(age*111)*strength*.63
end

local function blinkTrail(g,ax,ay,bx,by,rad,progress,landing)
  local strength=smooth(progress/.24)*(1-landing)
  local head=smooth((progress-.12)/.67)
  local points={}
  for i=0,14 do
    local t=head*i/14
    points[#points+1]=ax+(bx-ax)*t
    points[#points+1]=ay+(by-ay)*t-rad*(.28+math.sin(math.pi*t)*.53)
  end
  if head>0 then
    g.setColor(.48,.30,1,strength*.29);g.setLineWidth(rad*.31)
    g.line((table.unpack or unpack)(points))
    g.setColor(.86,.72,1,strength*.85);g.setLineWidth(math.max(1,rad*.066))
    g.line((table.unpack or unpack)(points))
  end
  for i=1,10 do
    local t=head-i*.072
    if t>0 then
      local x=ax+(bx-ax)*t
      local y=ay+(by-ay)*t-rad*(.28+math.sin(math.pi*t)*.53+math.sin(i*2.2+progress*7)*.20)
      local size=rad*(.045+(i%3)*.021)
      g.setColor(.73,.62,1,strength*(1-i/13))
      g.circle('fill',x,y,math.max(.7,size))
    end
  end
end

function M.draw(g,move,center,rad,drawToken)
  local path,look=move.route,move.profile
  local progress=math.min(1,move.elapsed/move.travel)
  local landing=smooth((move.elapsed-move.travel)/look.settle)
  local magic=move.class=='wizard'
  local x,y,lift,opacity,scale
  if magic then
    -- The token dissolves at its origin and reforms at its destination.
    local start,finish=path[1],path[#path]
    local ax,ay=center(start.r,start.c)
    local bx,by=center(finish.r,finish.c)
    blinkTrail(g,ax,ay,bx,by,rad,progress,landing)
    particles(g,ax,ay,rad,math.min(1,progress/.66),look,true)
    particles(g,bx,by,rad,math.min(1,(progress-.35)*.95+landing*.50),look,true)
    if progress<.38 then
      x,y=ax,ay
      opacity=1-smooth(progress/.38)
      lift=rad*.26*(1-opacity)
      scale=.90+opacity*.10
    else
      x,y=bx,by
      opacity=smooth((progress-.46)/.54)
      lift=rad*.24*(1-opacity)
      scale=.88+opacity*.12
    end
  else
    local advance=progress*(#path-1)
    local i=math.min(#path-1,math.floor(advance)+1)
    local from,to=path[i],path[i+1]
    local step=advance-i+1
    local t=smooth(step)
    local ax,ay=center(from.r,from.c)
    local bx,by=center(to.r,to.c)
    x,y=ax+(bx-ax)*t,ay+(by-ay)*t
    lift=rad*(math.sin(step*math.pi)*look.lift+.11*(1-smooth(progress/.16)))
    opacity=1
    scale=1+.024*math.sin(step*math.pi)-.075*look.impact*math.sin(landing*math.pi)
  end
  if opacity>.02 then
    g.setColor(.036,.028,.025,opacity*.43)
    g.circle('fill',x,y+rad*.12,rad*(.55-lift/rad*.30))
    drawToken(x,y-lift,scale,opacity)
  end
  if not magic and landing>0 then
    particles(g,x,y+rad*.53,rad,landing,look,false)
  end
end

return M
