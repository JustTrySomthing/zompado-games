local M = {}
local titles = {
  VICTORY='victory',
  DEFEAT='defeat',
}
local images, dust
function M.load(g)
  images={}
  for label,path in pairs(titles) do
    images[label]=g.newImage('art/finish-'..path..'.png')
  end
  dust=g.newImage('art/finish-dust.png')
end

function M.title(g,label,w,h,centerY,progress,settle,accent)
  local image=images[label]
  local iw,ih=image:getDimensions()
  local fit=math.min(w*.84/iw,h*.138/ih)
  local width,height=iw*fit,ih*fit
  g.push()
  g.translate(w*.5,centerY)
  g.rotate(label=='VICTORY' and -.055 or 0)
  g.scale(settle)
  local edge=math.min(w*.46,width*.5+w*.035)
  local top=height*.54
  local clip=math.min(top*.58,w*.04)
  local outline={-edge,-top+clip,-edge+clip,-top,edge-clip,-top,edge,-top+clip,
    edge,top-clip,edge-clip,top,-edge+clip,top,-edge,top-clip}
  g.setColor(.12,.089,.086,.85*progress)
  g.polygon('fill',outline)
  g.setLineWidth(math.max(1,w*.0035))
  g.setColor(accent[1],accent[2],accent[3],.55*progress)
  g.polygon('line',outline)
  g.setLineWidth(1)
  g.setColor(accent[1],accent[2],accent[3],.25*progress)
  g.line(-edge+clip+3,-top+3,edge-clip-3,-top+3)
  g.setColor(1,1,1,progress)
  g.draw(image,-width*.5,-height*.5,0,fit)
  g.pop()
end

function M.debris(g,x,base,size,age)
  if age<=0 or age>2.65 then return end
  local glow=math.max(0,1-age/.58)
  local settle=(1-math.min(1,age/2.65))^1.52
  for i=1,17 do
    local drift=(i*7%19-9)*.083
    local r=size*(.15+i%4*.075+age*.27)
    local px=x+size*drift*(.63+.69*age)
    local py=base-size*(.07+(i%5)*.035+age*(i%3==0 and .13 or -.045))+age^2*size*.031
    g.setColor(.33+glow*.44,.26+glow*.23,.23+glow*.09,settle*(i%3==0 and .59 or .37))
    g.draw(dust,px,py,0,r/40,r/64,40,40)
  end
end
return M
