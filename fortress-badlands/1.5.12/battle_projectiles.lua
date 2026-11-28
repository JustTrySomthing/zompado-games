local projectiles = {releasedArchers={}}

function projectiles.load(g)
  if not love.image or not love.image.newImageData then return end
  for team=1,2 do
    local file=('fighters/archer-%d.png'):format(team)
    local ok,source=pcall(love.image.newImageData,file)
    if ok then
      local release=source:clone()
      -- Reuse the painted archer and clear just the nocked arrow after release.
      -- Match the art at either end of the shaft, preserving the hands and bow.
      for x=133,319 do
        local y0=team==1 and 151.5 or 151
        local shaft=y0-(x-140)*.050
        for y=135,163 do
          local erase=(x<164 and math.abs(y-shaft)<6.9)
            or (x>=164 and x<270 and math.abs(y-shaft)<2.9)
            or (x>=291 and y<=152 and y>=137 and x>=291+math.max(0,y-149))
          if erase then
            if x>=172 then release:setPixel(x,y,0,0,0,0)
            else
              local sample=y+(y<=shaft and -8 or 9)
              release:setPixel(x,y,source:getPixel(x,sample))
            end
          end
        end
      end
      local loaded,image=pcall(g.newImage,release)
      if loaded then projectiles.releasedArchers[team]=image end
    end
  end
end

function projectiles.charge(g,x,y,size,amount)
  if amount<=0 then return end
  for step=8,1,-1 do
    local f=step/8
    g.setColor(1,.54,.23,amount*(1-f*.55)*.15)
    g.circle('fill',x,y,size*(.18+.70*f))
  end
  g.setColor(1,.90,.65,amount*.83)
  g.circle('fill',x,y,size*(.12+.13*amount))
end

-- The shaft, pale fletching and faceted, swept head follow the nocked arrow.
function projectiles.arrow(g,x,y,dx,dy,length,alpha)
  local d=math.sqrt(dx*dx+dy*dy)
  local ux,uy=dx/math.max(1,d),dy/math.max(1,d)
  local nx,ny=-uy,ux
  local function at(along,across)
    return x+(ux*along+nx*across)*length,y+(uy*along+ny*across)*length
  end
  local function poly(...)
    local vertices={}
    local p={...}
    for i=1,#p,2 do vertices[i],vertices[i+1]=at(p[i],p[i+1]) end
    g.polygon('fill',vertices)
  end
  local tx,ty=at(-1,.0)
  local hx,hy=at(-.085,0)
  g.setColor(.36,.192,.091,alpha);g.setLineWidth(math.max(1.4,length*.022))
  g.line(tx,ty,hx,hy)
  tx,ty=at(-.99,-.006)
  hx,hy=at(-.085,-.006)
  g.setColor(.80,.54,.29,alpha);g.setLineWidth(math.max(.6,length*.008))
  g.line(tx,ty,hx,hy)
  g.setColor(.68,.64,.55,alpha)
  poly(-.98,-.007,-.99,-.035,-.87,-.030,-.81,-.006,-.88,.006)
  g.setColor(.46,.42,.35,alpha)
  poly(-.99,.008,-.98,.031,-.88,.029,-.81,.006)
  g.setColor(.46,.45,.43,alpha)
  poly(0,0,-.135,-.037,-.113,0,-.135,.039)
  g.setColor(.86,.84,.77,alpha)
  poly(0,0,-.135,-.037,-.108,-.006)
  g.setColor(.62,.60,.56,alpha)
  poly(0,0,-.108,-.006,-.135,.039)
end

return projectiles
