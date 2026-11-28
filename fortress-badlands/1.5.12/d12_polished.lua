local drawGeometry=require('d12')

local materials={
  {{.58,.13,.20},{1,.51,.44}},
  {{.16,.34,.58},{.58,.84,1}},
}

local function materialColor(base,high,light,glint)
  return base[1]*light+high[1]*glint,base[2]*light+high[2]*glint,base[3]*light+high[3]*glint
end

local function tint(g,base,high,light,glint)
  g.setColor(materialColor(base,high,light,glint))
end

local fontCache
local function numeralFont(g,fallback)
  if fontCache==nil and g.newFont then
    local ok,font=pcall(g.newFont,'fonts/die-numerals.ttf',32)
    fontCache=ok and font or false
  end
  return fontCache or fallback
end

local faceMesh
local function polishedFace(g,poly,cy,r,base,high,light,reflection)
  if faceMesh==nil and g.newMesh then
    local ok,mesh=pcall(g.newMesh,5,'fan','stream')
    faceMesh=ok and mesh or false
  end
  if not faceMesh then
    tint(g,base,high,light,reflection)
    g.polygon('fill',poly)
    return
  end
  for j=1,10,2 do
    local y=poly[j+1]
    local brightness=(cy-y)/r
    local red,green,blue=materialColor(base,high,light+brightness*.38,
      reflection+math.max(0,brightness)*.11)
    faceMesh:setVertex((j+1)/2,poly[j],y,0,0,red,green,blue,1)
  end
  g.setColor(1,1,1,1)
  g.draw(faceMesh)
end

local function number(g,label,x,y,r,font,front,slant)
  local height=font.getHeight and font:getHeight() or font.size
  local room=r*.86
  local targetHeight=r*(label=='D12' and .43 or .55)
  local width=font.getWidth and font:getWidth(label) or #label*height*.60
  local fit=math.min(1,room/math.max(1,width),targetHeight/height)
  g.setFont(font)
  if g.push and g.translate and g.scale and g.rotate then
    g.push()
    g.translate(x,y)
    g.rotate(slant)
    g.scale(fit,fit*(front and 1 or .69))
    local textWidth=math.max(width+3,room/fit)
    local top=-height*.52
    -- A dark bevel above the inlay and a small reflected edge below it.
    g.setColor(.095,.042,.068,.90)
    g.printf(label,-textWidth*.5,top-.8,textWidth,'center')
    g.setColor(.98,.81,.53,front and .95 or .68)
    g.printf(label,-textWidth*.5,top+.65,textWidth,'center')
    g.setColor(1,.94,.78,front and 1 or .78)
    g.printf(label,-textWidth*.5,top,textWidth,'center')
    g.pop()
  elseif front then
    g.setColor(1,.94,.78,1)
    g.printf(label,x-room*.5,y-height*.5,room,'center')
  end
end

local function finish(g,cx,cy,team,r,font,idleLabel,bounce,points,visible,faces)
  local material=materials[team] or materials[2]
  local base,high=material[1],material[2]
  if g.newMesh then font=numeralFont(g,font) end
  if g.ellipse then
    for i=4,1,-1 do
      g.setColor(.015,.012,.025,.08)
      g.ellipse('fill',cx,cy+r*.92,r*(.61+i*.12+bounce*.12/r),r*(.09+i*.035))
    end
  end
  for _,f in ipairs(visible) do
    local outer,inner={},{}
    local x,y=0,0
    for _,id in ipairs(faces[f.id]) do
      local p=points[id]
      outer[#outer+1]=p[1]
      outer[#outer+1]=p[2]
      x,y=x+p[1]/5,y+p[2]/5
    end
    local light=.63+f.z*.43-f.y*.23-f.x*.16
    local reflection=math.max(0,1-math.abs(f.x+.24)*2.1-math.abs(f.y+.24)*1.55)*.19
    for j=1,10,2 do
      inner[j]=outer[j]+(x-outer[j])*.124
      inner[j+1]=outer[j+1]+(y-outer[j+1])*.124
    end
    tint(g,base,high,light*.78,reflection*.28)
    g.polygon('fill',outer)
    for j=1,10,2 do
      local k=(j+1)%10+2
      local ax,ay,bx,by=outer[j],outer[j+1],outer[k-1],outer[k]
      local direction=((ax+bx)*.5-x)*.39+((ay+by)*.5-y)*.70
      local gloss=math.max(0,math.min(.49,.19-direction/r*.78))
      tint(g,base,high,light*.80+gloss*.20,gloss)
      g.polygon('fill',ax,ay,bx,by,inner[k-1],inner[k],inner[j],inner[j+1])
    end
    polishedFace(g,inner,y,r,base,high,light,reflection)
    if f.z>.41 then
      local front=f.z>.73
      local label=front and idleLabel or tostring(f.id)
      local slant=front and f.x*.2 or f.x*.55+f.y*.19
      number(g,label,x,y,front and r or r*.63,font,front,slant)
    end
  end
end

-- Reuse high-resolution surfaces by size. Halving linearly averages the
-- silhouette and bevel edges while leaving each roll in the same position.
local surfaces={}
local canSupersample
local function canvasFor(g,side)
  if canSupersample==false or not (g.newCanvas and g.getCanvas and g.setCanvas and g.push
      and g.pop and g.origin and g.scale and g.clear and g.draw and g.setBlendMode) then return end
  if not surfaces[side] then
    local ok,canvas=pcall(g.newCanvas,side*2,side*2,{dpiscale=1})
    if not ok then canSupersample=false;return end
    canvas:setFilter('linear','linear')
    surfaces[side]=canvas
  end
  return surfaces[side]
end

return function(g,cx,cy,face,spin,team,r,font,idleLabel)
  local side=math.ceil(r*3/8)*8
  local canvas=canvasFor(g,side)
  if not canvas then
    return drawGeometry(g,cx,cy,face,spin,team,r,font,idleLabel,finish)
  end
  local previous=g.getCanvas()
  g.push('all')
  if not pcall(g.setCanvas,canvas) then
    g.pop()
    canSupersample=false
    return drawGeometry(g,cx,cy,face,spin,team,r,font,idleLabel,finish)
  end
  g.origin()
  g.clear(0,0,0,0)
  g.scale(2,2)
  drawGeometry(g,side/2,side/2,face,spin,team,r,font,idleLabel,finish)
  g.setCanvas(previous)
  g.pop()
  g.push('all')
  g.setColor(1,1,1,1)
  g.setBlendMode('alpha','premultiplied')
  g.draw(canvas,math.floor(cx-side/2+.5),math.floor(cy-side/2+.5),0,.5,.5)
  g.pop()
end
