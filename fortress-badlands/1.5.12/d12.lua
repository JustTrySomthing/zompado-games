-- Projected dodecahedron. Each numbered pentagon has a fixed normal.
local vertices = {
  {-1,-1,-1},
  {-1,-1,1},
  {-1,1,-1},
  {-1,1,1},
  {1,-1,-1},
  {1,-1,1},
  {1,1,-1},
  {1,1,1},
  {0,-0.61803399,-1.618034},
  {-0.61803399,-1.618034,0},
  {-1.618034,0,-0.61803399},
  {0,-0.61803399,1.618034},
  {-0.61803399,1.618034,0},
  {1.618034,0,-0.61803399},
  {0,0.61803399,-1.618034},
  {0.61803399,-1.618034,0},
  {-1.618034,0,0.61803399},
  {0,0.61803399,1.618034},
  {0.61803399,1.618034,0},
  {1.618034,0,0.61803399},
}
local faces = {
  {5,16,10,1,9},
  {17,11,1,10,2},
  {3,15,9,1,11},
  {16,6,12,2,10},
  {4,13,3,11,17},
  {15,7,14,5,9},
  {19,7,15,3,13},
  {14,20,6,16,5},
  {18,4,17,2,12},
  {8,19,13,4,18},
  {7,19,8,20,14},
  {8,18,12,6,20},
}
local normals = {
  {0,-0.85065081,-0.52573111},
  {-0.85065081,-0.52573111,0},
  {-0.52573111,0,-0.85065081},
  {0,-0.85065081,0.52573111},
  {-0.85065081,0.52573111,0},
  {0.52573111,0,-0.85065081},
  {0,0.85065081,-0.52573111},
  {0.85065081,-0.52573111,0},
  {-0.52573111,0,0.85065081},
  {0,0.85065081,0.52573111},
  {0.85065081,0.52573111,0},
  {0.52573111,0,0.85065081},
}

return function(g,cx,cy,face,spin,team,r,font,idleLabel,finish)
  local angle=spin and spin*13 or 0
  local bounce=spin and math.abs(math.sin(angle*.70))*r*.23*(1-math.min(1,spin*.8)) or 0
  local normal=normals[face]
  local ax,ay=normal[2],-normal[1]
  local length=math.sqrt(ax*ax+ay*ay)
  ax,ay=ax/length,ay/length
  local bx,by,bz=-ay*normal[3],ax*normal[3],ay*normal[1]-ax*normal[2]
  local sinX,cosX=math.sin(angle*.93+.18),math.cos(angle*.93+.18)
  local sinY,cosY=math.sin(angle*.65-.22),math.cos(angle*.65-.22)
  local sinZ,cosZ=math.sin(angle*.44+.12),math.cos(angle*.44+.12)
  local function rotate(v)
    local x,y,z=v[1],v[2],v[3]
    if not spin then
      x,y,z=ax*x+ay*y,bx*x+by*y+bz*z,normal[1]*x+normal[2]*y+normal[3]*z
    end
    y,z=y*cosX-z*sinX,y*sinX+z*cosX
    x,z=x*cosY+z*sinY,-x*sinY+z*cosY
    return x*cosZ-y*sinZ,x*sinZ+y*cosZ,z
  end
  local points={}
  for i,v in ipairs(vertices) do
    local x,y,z=rotate(v)
    local perspective=r*.59/(1-z*.13)
    points[i]={cx+x*perspective,cy-bounce+y*perspective}
  end
  local red,green,blue=.29,.54,.85
  if team==1 then red,green,blue=.83,.26,.30 end
  local visible={}
  for i,n in ipairs(normals) do
    local x,y,z=rotate(n)
    if z>(finish and .179 or .16) then visible[#visible+1]={id=i,x=x,y=y,z=z} end
  end
  table.sort(visible,function(a,b) return a.z<b.z end)
  if finish then
    return finish(g,cx,cy,team,r,font,idleLabel,bounce,points,visible,faces)
  end
  g.setColor(.005,.012,.035,.62)
  if g.ellipse then g.ellipse('fill',cx,cy+r*.95,r*.72,r*.14) end
  for _,f in ipairs(visible) do
    local poly={}
    local px,py=0,0
    for _,vertex in ipairs(faces[f.id]) do
      local point=points[vertex]
      poly[#poly+1]=point[1];poly[#poly+1]=point[2]
      px,py=px+point[1]/5,py+point[2]/5
    end
    local shade=.58+.34*f.z-.20*f.y-.12*f.x
    g.setColor(red*shade,green*shade,blue*shade,1)
    g.polygon('fill',poly)
    g.setLineWidth(math.max(1,r*.045))
    g.setColor(.09,.05,.09,.95);g.polygon('line',poly)
    g.setLineWidth(1)
    g.setColor(1,.80,.50,.63)
    g.line(poly[1],poly[2],poly[3],poly[4],poly[5],poly[6])
    if f.z>.73 then
      g.setColor(1,.92,.78,1);g.setFont(font)
      local height=font.getHeight and font:getHeight() or font.size
      g.printf(idleLabel or tostring(f.id),px-r*.56,py-height*.5,r*1.12,'center')
    end
  end
end
